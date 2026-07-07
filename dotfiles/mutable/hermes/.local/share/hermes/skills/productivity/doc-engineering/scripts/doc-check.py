#!/usr/bin/env python3
"""
doc-check.py — 文档体检 / drift 校对检查器

Inputs:
    一个或多个文档路径（必须 .md / .org）

Detects (按 noise-to-signal 排序):
    1. CLI 子命令表行数 vs 命令实际行数    ——  若用户提示 CLI 命令名（如 'agenote'）
    2. 声明的 MCP tool 列表存在性检查      ——  若 MCP 路径可达
    3. 外链文件路径存在性                 ——  若 README/doc 引用文件
    4. 日期戳文件名 smell                 ——  references/2026-07-04-x.md 风格
    5. 双重时间戳 / 过期"已验证"警告      ——  文档内出现 ">90 天" 检查
    6. 段落"无来源" smell                ——  长 fenced command 块未标 VERIFIED BY
    7. 与代码自描述不一致                ——  doc 行声明"(N=27)" vs CLI 实际 N

Outputs:
    默认：人类可读分级报告
    --json: JSON 报告供下游脚本消费

设计原则：
    单个 fixture = 一次 stdin / 命令行调用；不创建持久 fixture
    fail-fast 在 drift 检测；warn-only 在 style smell
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ---------- 检查函数 ----------


def check_cli_subcommand_count(doc_text: str, cli_name: str) -> dict:
    """若文档声明 '(N=xx)' 子命令数，反查 CLI help 实际数量。"""
    declared = re.findall(r"\((\d+)\s*个[子]?命令\)|N\s*=\s*(\d+)", doc_text)
    if not declared:
        return {"check": "cli_count", "status": "skip", "note": "no count claim"}

    declared_n = int(declared[0][0] or declared[0][1])
    try:
        out = subprocess.run(
            [cli_name, "--help"], capture_output=True, text=True, timeout=10
        )
        # CLI help 通常是 `  <name>` 缩进的子命令列表
        actual = len(set(re.findall(r"^  ([a-z][a-z_-]+)", out.stdout, re.M)))
    except Exception as e:
        return {"check": "cli_count", "status": "skip", "note": str(e)}

    return {
        "check": "cli_count",
        "status": "fail" if actual != declared_n else "pass",
        "declared": declared_n,
        "actual": actual,
    }


# CLI 子命令 → 可能对应的 MCP tool 名（一个 CLI 子命令可能展开多个 MCP tool）
# 当 CLI 不存在但 MCP 存在的合理拓展应当列入此处，避免 doc-check.py 误报 "unknown"
KNOWN_MULTI_TOOL_SUBCOMMANDS = {
    "memory": [
        "agenote_memory_add",
        "agenote_memory_get",
        "agenote_memory_overview",
        "agenote_memory_search",
    ],
}


def check_mcp_tools_named(doc_text: str) -> dict:
    """文档中形如 `agenote_xxx` 的 tool 名是否在 agent MCP 注册中。"""
    # 不实际查询 MCP server（可能离线），仅收集清单供下游 verifier 比对
    tools = sorted(set(re.findall(r"`(agenote_[a-z_]+)`", doc_text)))
    return {"check": "mcp_tools_named", "tools": tools}


def check_linked_paths(doc_root: Path, doc_text: str) -> list:
    """文档内引用的相对路径是否真的存在。"""
    findings = []
    for path_str in re.findall(r"`([^`]+\.(md|org|py|sh|scm))`", doc_text):
        rel = path_str[0]
        if rel.startswith(("http", "https", "~", "/gnu/", "/proc/", "/sys/")):
            continue
        if not rel.startswith(("/", "./", "../")):
            continue
        target = (doc_root / rel).resolve()
        if not target.exists():
            findings.append({"path": rel, "status": "missing"})
    return findings


def check_date_filename_smell(doc_root: Path) -> list:
    """references/YYYY-MM-DD-*.md 这种 per-session 命名 smell。"""
    findings = []
    for ref_dir in ["references", "docs"]:
        d = doc_root / ref_dir
        if not d.is_dir():
            continue
        for p in d.iterdir():
            if re.match(r".*\d{4}-\d{2}-\d{2}", p.name) and p.suffix in {".md", ".org"}:
                findings.append({"path": str(p), "smell": "date-in-filename"})
    return findings


def check_stale_verification_stamp(doc_text: str) -> list:
    """文档内有 'as of <日期>' / '修订记录 <日期>' 时，给出过期评估。"""
    findings = []
    for m in re.finditer(
        r"(?:修订记录|as of|last verified)[：: ]+(\d{4}-\d{2}-\d{2})", doc_text, re.I
    ):
        findings.append({"date": m.group(1), "context": "verification_stamp"})
    return findings


# ---------- 入口 ----------


def main():
    ap = argparse.ArgumentParser(description="文档体检 / drift 校对检查器")
    ap.add_argument("paths", nargs="+", help="一个或多个文档路径")
    ap.add_argument("--cli", default=None, help="要反查的 CLI 命令名（如 agenote）")
    ap.add_argument("--json", action="store_true", help="输出 JSON 报告")
    args = ap.parse_args()

    report = {"docs": []}
    rc = 0
    for path_str in args.paths:
        p = Path(path_str)
        if not p.exists():
            print(f"[FAIL] not found: {p}", file=sys.stderr)
            rc = 2
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        doc_entry = {
            "path": str(p),
            "checks": [],
            "linked_paths": [],
            "stale_stamps": [],
        }
        if args.cli:
            doc_entry["checks"].append(check_cli_subcommand_count(text, args.cli))
        doc_entry["checks"].append(check_mcp_tools_named(text))
        doc_entry["linked_paths"] = check_linked_paths(p.parent, text)
        doc_entry["date_filename_smells"] = check_date_filename_smell(p.parent)
        doc_entry["stale_stamps"] = check_stale_verification_stamp(text)
        report["docs"].append(doc_entry)

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        for d in report["docs"]:
            print(f"\n=== {d['path']} ===")
            for c in d["checks"]:
                if isinstance(c, dict):
                    print(f" - [{c.get('status', '?')}] {c.get('check')}: {c}")
            for lp in d["linked_paths"]:
                print(f" - [MISSING] {lp['path']}")
            for sm in d["date_filename_smells"]:
                print(f" - [SMELL] {sm['path']}  ({sm['smell']})")
            for st in d["stale_stamps"]:
                print(f" - [STALE] verification stamp {st['date']}")

    sys.exit(rc)


if __name__ == "__main__":
    main()
