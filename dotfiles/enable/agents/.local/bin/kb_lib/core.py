# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_core — 知识库核心模块：常量、工具函数、索引管理、Org 解析、搜索辅助"""

import json
import os
import re
import shlex
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# 配置常量
# ═══════════════════════════════════════════════════════════════════════════════

# ── 路径 ──────────────────────────────────────────────────────────────────────
KB_ROOT = Path(
    os.environ.get("KB_ROOT", str(Path.home() / "Documents" / "Org"))
)
KB_EXPERIENCES = KB_ROOT / "experiences"
KB_MEMORY = KB_ROOT / "MEMORY.org"
KB_MEMORIES = KB_ROOT / "memories"
KB_PROJECTS = KB_MEMORIES / "projects"
KB_INDEX = KB_ROOT / "index.json"
KB_INBOX = KB_ROOT / "inbox.org"

# ── 阈值 ──────────────────────────────────────────────────────────────────────
STALE_DAYS = 30
DEFAULT_LIST_COUNT = 20

MEMORY_SECTIONS = ["feedback", "project", "reference", "deprecated"]


# ═══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════════════════════════════


def die(msg: str) -> None:
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def now() -> str:
    return datetime.now().strftime("%Y-%m-%d %a %H:%M")


def today() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def timestamp_id() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def _init_memory_template() -> None:
    date_str = datetime.now().strftime("%Y-%m-%d %a")
    sections = [f"#+title: MEMORY", f"#+date: [{date_str}]"]
    sections.append("")
    sections.append("#+BEGIN_COMMENT")
    sections.append("MEMORY.org — 统一记忆索引")
    sections.append("")
    sections.append("设计原则：")
    sections.append("1. 记忆只存储无法从当前代码/项目状态推导的信息")
    sections.append("2. feedback 记录用户的行为偏好和工作癖好")
    sections.append("3. project 记忆按项目拆分为独立文件，通过路径/名称检索")
    sections.append("4. 记忆是时间点观察，不是实时状态——引用前先验证")
    sections.append("5. MEMORY 偏重癖好偏好，知识库偏重可复用知识")
    sections.append("6. 带 ⚠ 标记的条目为陈旧记忆，需验证后才能作为决策依据")
    sections.append("#+END_COMMENT")
    for sec in MEMORY_SECTIONS:
        sections.append("")
        sections.append(f"* {sec}")
    KB_MEMORY.write_text("\n".join(sections) + "\n", encoding="utf-8")


def ensure_dirs() -> None:
    KB_EXPERIENCES.mkdir(parents=True, exist_ok=True)
    KB_MEMORIES.mkdir(parents=True, exist_ok=True)
    KB_PROJECTS.mkdir(parents=True, exist_ok=True)

    if not KB_INBOX.exists():
        KB_INBOX.write_text(
            f"#+title: inbox\n#+date: [{now()}]\n\n",
            encoding="utf-8",
        )

    if not KB_MEMORY.exists():
        _init_memory_template()

    if not KB_INDEX.exists():
        _save_index({"version": 1, "updated": "", "total": 0, "cards": []})


def parse_org_prop(content: str, key: str) -> str:
    m = re.search(rf":{key}:\s*(.+)", content)
    return m.group(1).strip() if m else ""


def read_org_title(content: str) -> str:
    m = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    return m.group(1).strip() if m else "unknown"


def _card_dict(filepath: Path) -> dict | None:
    if filepath.is_symlink():
        return None
    content = filepath.read_text(encoding="utf-8")
    card_id = parse_org_prop(content, "ID") or filepath.stem.split("-")[0]
    created = parse_org_prop(content, "CREATED")
    if created:
        created = re.sub(r"[\[\]]", "", created).split()[0]
    entry_type = parse_org_prop(content, "ENTRY_TYPE") or None

    tags_line = ""
    m = re.search(r":(\S+)::", content)
    if m:
        tags_line = m.group(1)
    raw_tags = tags_line.split(":") if tags_line else []
    expanded_tags = []
    for tag in raw_tags:
        expanded_tags.extend(t.strip() for t in tag.split(",") if t.strip())

    return {
        "id": card_id,
        "file": str(filepath.relative_to(KB_ROOT)),
        "title": read_org_title(content),
        "category": parse_org_prop(content, "CATEGORY") or "general",
        "tech": parse_org_prop(content, "TECH") or "",
        "type": parse_org_prop(content, "TYPE") or "workflow",
        "owner": parse_org_prop(content, "OWNER") or "ai",
        "entry_type": entry_type,
        "status": parse_org_prop(content, "STATUS") or "done",
        "last_used": parse_org_prop(content, "LAST_USED"),
        "last_verified": parse_org_prop(content, "LAST_VERIFIED"),
        "created": created or "",
        "tags": expanded_tags,
    }


def _load_index() -> dict:
    if KB_INDEX.exists():
        try:
            return json.loads(KB_INDEX.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {"version": 1, "updated": "", "total": 0, "cards": []}


def _save_index(index: dict) -> None:
    index["updated"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    index["total"] = len(index["cards"])
    KB_INDEX.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _rebuild_index() -> dict:
    cards = []
    for f in sorted(
        KB_EXPERIENCES.rglob("*.org"), key=lambda p: p.stat().st_mtime, reverse=True
    ):
        d = _card_dict(f)
        if d:
            cards.append(d)
    return {"version": 1, "updated": "", "total": len(cards), "cards": cards}


def _iter_search_targets() -> list[Path]:
    targets = []
    if KB_EXPERIENCES.exists():
        targets.extend(
            f
            for f in sorted(KB_EXPERIENCES.rglob("*.org"))
            if f.is_file() and not f.is_symlink()
        )
    if KB_MEMORY.exists():
        targets.append(KB_MEMORY)
    return targets


def _query_terms(query: str) -> list[str]:
    try:
        pieces = shlex.split(query)
    except ValueError:
        pieces = query.split()

    terms = []
    for piece in pieces:
        for term in re.split(r"[/,，、]+", piece):
            term = term.strip()
            if term:
                terms.append(term)
    if not terms and query.strip():
        terms = [query.strip()]

    unique = []
    seen = set()
    for term in terms:
        key = term.casefold()
        if key not in seen:
            seen.add(key)
            unique.append(term)
    return unique


def _line_contains_any(line: str, needles: list[str], case_sensitive: bool) -> bool:
    haystack = line if case_sensitive else line.casefold()
    return any(needle in haystack for needle in needles)


def _merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    if not ranges:
        return []
    ranges = sorted(ranges)
    merged = [ranges[0]]
    for start, end in ranges[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end + 1:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))
    return merged


def _range_score(
    lines: list[str], start: int, end: int, needles: list[str], case_sensitive: bool
) -> int:
    block = "\n".join(lines[start : end + 1])
    haystack = block if case_sensitive else block.casefold()
    matched_terms = [needle for needle in needles if needle in haystack]
    return len(matched_terms) * 100 + sum(
        haystack.count(needle) for needle in matched_terms
    )
