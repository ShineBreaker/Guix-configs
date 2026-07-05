# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""ag_lib.extract — cross-agent conversation extraction common layer.

Provide XDG-aware path resolution, SQLite read-only open helper, title extractor.
Each source (opencode/crush/codex/claude/pi) lives in its own file with signature:
    (list[ReconciledFact], list[str])
"""

from __future__ import annotations

import os
import re
import sqlite3
from pathlib import Path


# ── XDG-aware path resolution ──────────────────────────────────

def resolve_xdg_path(env_var: str, default: str) -> Path:
    """Resolve path respecting env var, then XDG base dirs.

    Lookup order:
      1. os.environ[env_var] (direct override)
      2. $XDG_DATA_HOME / $XDG_CONFIG_HOME from default placeholder
      3. expanduser fallback (~/...)

    default may use $XDG_DATA_HOME/$XDG_CONFIG_HOME placeholders:
        resolve_xdg_path('CODEX_HOME', '$XDG_CONFIG_HOME/codex')
    """
    val = os.environ.get(env_var)
    if val:
        return Path(val).expanduser()

    # Resolve $XDG_*_HOME placeholders in default
    m = re.match(r'\$XDG_(\w+)_HOME', default)
    if m:
        xdg_key = f"XDG_{m.group(1)}_HOME"
        xdg_val = os.environ.get(xdg_key)
        if xdg_val:
            remainder = default.split('/', 1)[1] if '/' in default else ''
            return Path(xdg_val) / remainder

    return Path(default.replace('~', str(Path.home()))).expanduser()


# ── SQLite read-only open (triple protection) ─────────────────

def open_sqlite_ro(db_path: Path) -> sqlite3.Connection:
    """Triple read-only SQLite protection:
    1. file: URI + mode=ro (SQLite layer rejects writes)
    2. PRAGMA query_only = 1 (connection layer rejects DML/DDL)
    3. Caller never constructs write statements (convention)
    """
    if not db_path.exists():
        raise FileNotFoundError(f"DB 不存在: {db_path}")
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = 1")
    return conn


# ── Title extraction helper ───────────────────────────────────

_TITLE_BRACKET_RE = re.compile(r"^【([^】]+)】")
_TITLE_SENT_RE = re.compile(r"[^。\n!?:;]+")


def extract_title(content: str, max_len: int = 60) -> str:
    """Unified title extractor: 【...】 bracket → first sentence → truncate."""
    m = _TITLE_BRACKET_RE.match(content.strip())
    if m:
        return m.group(1).strip()[:max_len]
    first = _TITLE_SENT_RE.match(content.strip())
    raw = (first.group(0).strip() if first else content.strip())[:40]
    return raw or "(untitled)"


# ── Orchestration ──────────────────────────────────────────────
# run_extract 是 extract 子命令/ag_note_extract MCP tool 的单一真相源。
# 抽取器在函数内 lazy import，与 reconcile.py 的 KNOWN_SOURCES 模式一致，
# 避免 ag_lib.extract.* 在模块加载时拉起整条 sqlite/reconcile 依赖链。

# source 名 → extractor 解析器（lazy 解析，避免顶层 import 循环）
def _resolve_extractors() -> dict:
    """返回 source → extractor callable 的映射。lazy import。"""
    from ag_lib.extract import opencode, crush, codex, claude, pi, zcode
    from ag_lib.reconcile import extract_hermes

    return {
        "opencode": opencode.extract_opencode,
        "crush": crush.extract_crush,
        "codex": codex.extract_codex,
        "claude": claude.extract_claude,
        "pi": pi.extract_pi,
        "hermes": extract_hermes,
        "zcode": zcode.extract_zcode,
    }


def run_extract(
    source: str = "all",
    date: str = "",
    output_dir: str = "",
    dry_run: bool = False,
) -> dict:
    """跨 agent 对话抽取编排：把 7 个 AI 工具的原始对话抽取为 Org-mode 文件。

    与 reconcile_source 的区别：
      - reconcile_source：抽取**已沉淀的经验**（agent memory store），写 .reconcile/index.json
      - run_extract：抽取**原始对话**（DB/JSONL），输出 Org 文件供人/agent 提炼新经验

    Args:
        source: opencode | crush | codex | claude | pi | hermes | zcode | all
        date: 目标日期 YYYY-MM-DD（默认昨天；空字符串 = 不按日期过滤）
        output_dir: 输出目录（默认 ~/Documents/Org/conversations/<date>/）
        dry_run: False 只返回报告不落盘（默认）；显式 --dry-run 才不写盘

    Returns:
        dict: {source, total_facts, output_dir, files: [path, ...], errors: [...], dry_run}
        未知 source 时返回 {"error": ...}。
    """
    from datetime import datetime, timedelta

    extractors = _resolve_extractors()

    if source == "all":
        selected = list(extractors.keys())
    elif source in extractors:
        selected = [source]
    else:
        return {"error": f"未知 source: {source}；可选: {sorted(extractors)}"}

    # 输出目录
    if not output_dir:
        target_date = date or (datetime.now() - timedelta(days=1)).strftime("%Y-%m-%d")
        output_dir = f"~/Documents/Org/conversations/{target_date}"
    out_path = Path(output_dir).expanduser()
    if not dry_run:
        out_path.mkdir(parents=True, exist_ok=True)

    files: list[str] = []
    errors: list[str] = []
    total = 0
    for src in selected:
        try:
            facts, errs = extractors[src]()
            total += len(facts)
            errors.extend(errs)
            if dry_run:
                continue
            src_file = out_path / f"{src}.org"
            lines: list[str] = [
                f"#+TITLE: {src} conversations",
                f"#+DATE: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
                f"#+SOURCE: {src}",
                f"#+TOTAL: {len(facts)}",
                "",
            ]
            for f in facts[:500]:  # 安全上限：每源最多 500 条
                lines.append(f"* {f.title}")
                lines.append(f":PROPERTIES:")
                lines.append(f":ID: {f.id}")
                lines.append(f":CATEGORY: {f.category}")
                lines.append(f":WEIGHT: {f.weight}")
                lines.append(f":END:")
                lines.append("")
                lines.append(f.content[:3000])
                lines.append("")
            src_file.write_text("\n".join(lines), encoding="utf-8")
            files.append(str(src_file))
        except Exception as e:
            errors.append(f"{src}: {e}")

    return {
        "source": source,
        "total_facts": total,
        "output_dir": str(out_path),
        "files": files,
        "errors": errors,
        "dry_run": dry_run,
    }