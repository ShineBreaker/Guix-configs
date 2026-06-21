# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_cards — 知识库卡片检索（只读）"""

import argparse
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

from kb_lib.core import (  # noqa: E402
    KB_ROOT,
    KB_EXPERIENCES,
    DEFAULT_LIST_COUNT,
    die,
    parse_org_prop,
    read_org_title,
    _card_dict,
    _load_index,
    _save_index,
    _rebuild_index,
    _iter_search_targets,
    _query_terms,
    _line_contains_any,
    _merge_ranges,
    _range_score,
    ensure_dirs,
)


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: get — 读取卡片
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_get(args: argparse.Namespace) -> None:
    """读取指定卡片的完整内容。支持完整路径或 ID 部分匹配。"""
    target = args.target
    if not target:
        die("用法: kb get <卡片文件名或ID>")

    p = Path(target)
    if p.is_absolute():
        try:
            p.resolve().relative_to(KB_ROOT.resolve())
        except ValueError:
            die(f"路径超出知识库范围: {target}")
    if p.is_file():
        print(p.read_text(encoding="utf-8"), end="")
        return

    candidates = list(KB_EXPERIENCES.rglob(f"*{target}*"))
    candidates = [c for c in candidates if not c.is_symlink() and c.is_file()]
    if candidates:
        print(candidates[0].read_text(encoding="utf-8"), end="")
        return

    die(f"未找到卡片: {target}")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: list — 列出卡片
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_list(args: argparse.Namespace) -> None:
    """列出经验卡片，支持过滤和数量限制。输出 JSON。"""
    recent = (
        args.recent
        if args.recent is not None
        else (0 if args.all else DEFAULT_LIST_COUNT)
    )
    index = _load_index()
    matched = []
    for c in index["cards"]:
        if args.category and c["category"] != args.category:
            continue
        if args.type and c["type"] != args.type:
            continue
        if args.owner and c["owner"] != args.owner:
            continue
        matched.append(c)
        if recent > 0 and len(matched) >= recent:
            break

    compact = [
        {
            k: c.get(k, "")
            for k in ("id", "title", "category", "type", "tech", "owner", "created")
        }
        for c in matched
    ]
    print(json.dumps(compact, ensure_ascii=False, indent=2))


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: search — 全文检索
# ═══════════════════════════════════════════════════════════════════════════════

def _make_search_snippet(
    match: dict, normalized_terms: list[str], case_sensitive: bool
) -> str:
    lines = match["content"].splitlines()
    hit_indexes = [
        i
        for i, line in enumerate(lines)
        if _line_contains_any(line, normalized_terms, case_sensitive)
    ]
    if not hit_indexes:
        return ""
    start = max(0, hit_indexes[0] - 2)
    end = min(len(lines) - 1, hit_indexes[0] + 2)
    snippet = "\n".join(lines[start : end + 1])
    if len(snippet) > 200:
        snippet = snippet[:200] + "..."
    return snippet


def cmd_search(args: argparse.Namespace) -> None:
    """在 experiences/ 和 MEMORY.org 中全文检索。"""
    query = args.query
    context = args.context

    if args.json and args.regex:
        die("--json 与 --regex 互斥；--regex 模式只支持人类可读输出")

    if args.regex:
        targets = [str(KB_EXPERIENCES)]
        if shutil.which("rg"):
            cmd = ["rg", "--color=never", "-n", "-C", str(context), query] + targets
        else:
            cmd = ["grep", "-r", "-n", "-C", str(context), query] + targets

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            print(result.stdout, end="")
        else:
            print(f"未找到匹配: {query}")
        return

    terms = _query_terms(query)
    if not terms:
        die("必须提供搜索关键词")

    normalized_terms = terms if args.case_sensitive else [t.casefold() for t in terms]
    normalized_phrase = query if args.case_sensitive else query.casefold()
    matches = []

    for filepath in _iter_search_targets():
        try:
            content = filepath.read_text(encoding="utf-8")
        except OSError:
            continue

        haystack = content if args.case_sensitive else content.casefold()
        term_hits = [
            term for raw, term in zip(terms, normalized_terms) if term in haystack
        ]
        if not term_hits:
            continue
        if args.all_terms and len(term_hits) != len(terms):
            continue

        occurrence_count = sum(haystack.count(term) for term in term_hits)
        phrase_bonus = 50 if normalized_phrase and normalized_phrase in haystack else 0
        title = read_org_title(content)
        title_haystack = title if args.case_sensitive else title.casefold()
        title_bonus = 25 * sum(1 for term in term_hits if term in title_haystack)
        score = len(term_hits) * 100 + occurrence_count + phrase_bonus + title_bonus

        matches.append(
            {
                "filepath": filepath,
                "content": content,
                "score": score,
                "matched": [
                    raw
                    for raw, term in zip(terms, normalized_terms)
                    if term in haystack
                ],
                "title": title,
            }
        )

    if not matches:
        if args.json:
            print(json.dumps([], ensure_ascii=False, indent=2))
        else:
            print(f"未找到匹配: {query}")
        return

    matches.sort(key=lambda item: (-item["score"], str(item["filepath"])))
    limit = max(1, args.limit)

    if args.json:
        results = []
        for match in matches[:limit]:
            card_id = (
                parse_org_prop(match["content"], "ID")
                or match["filepath"].stem.split("-")[0]
            )
            results.append(
                {
                    "id": card_id,
                    "title": match["title"],
                    "score": match["score"],
                    "snippet": _make_search_snippet(
                        match, normalized_terms, args.case_sensitive
                    ),
                }
            )
        print(json.dumps(results, ensure_ascii=False, indent=2))
        return

    for idx, match in enumerate(matches[:limit]):
        filepath = match["filepath"]
        rel = (
            filepath.relative_to(KB_ROOT)
            if filepath.is_relative_to(KB_ROOT)
            else filepath
        )
        print(
            f"== {rel} | score={match['score']} | matched={', '.join(match['matched'])} =="
        )
        if match["title"] != "unknown":
            print(f"title: {match['title']}")

        lines = match["content"].splitlines()
        hit_indexes = [
            i
            for i, line in enumerate(lines)
            if _line_contains_any(line, normalized_terms, args.case_sensitive)
        ]
        ranges = _merge_ranges(
            [
                (max(0, i - context), min(len(lines) - 1, i + context))
                for i in hit_indexes
            ]
        )
        selected_ranges = sorted(
            sorted(
                ranges,
                key=lambda r: (
                    -_range_score(
                        lines, r[0], r[1], normalized_terms, args.case_sensitive
                    ),
                    r[0],
                ),
            )[: max(1, args.max_blocks)]
        )
        for start, end in selected_ranges:
            for line_idx in range(start, end + 1):
                sep = ":" if line_idx in hit_indexes else "-"
                print(f"{filepath}{sep}{line_idx + 1}{sep}{lines[line_idx]}")
            if (start, end) != selected_ranges[-1]:
                print("--")
        if idx != min(len(matches), limit) - 1:
            print()


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: fields — 列出已有字段值
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_fields(args: argparse.Namespace) -> None:
    """从 JSON 索引统计已有的 category/tech/type/owner 值及出现次数。"""
    show = {
        "category": args.category,
        "tech": args.tech,
        "type": args.type_,
        "owner": args.owner,
    }
    if not any(show.values()):
        for k in show:
            show[k] = True

    counters = {k: Counter() for k in show}
    index = _load_index()

    for c in index["cards"]:
        if show["category"] and c.get("category"):
            counters["category"][c["category"]] += 1
        if show["tech"] and c.get("tech"):
            counters["tech"][c["tech"]] += 1
        if show["type"] and c.get("type"):
            counters["type"][c["type"]] += 1
        if show["owner"] and c.get("owner"):
            counters["owner"][c["owner"]] += 1

    labels = {"category": "category", "tech": "tech", "type": "type", "owner": "owner"}
    if args.json:
        payload = {
            key: [
                {"name": name, "count": cnt}
                for name, cnt in sorted(counters[key].items())
            ]
            for key in labels
            if show[key]
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return

    for key, label in labels.items():
        if show[key]:
            print(f"── {label} ──")
            if not counters[key]:
                print("  (无)")
            else:
                for k, c in sorted(counters[key].items()):
                    print(f"  {k} ({c})")


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: tags — 按标签检索
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_tags(args: argparse.Namespace) -> None:
    """按标签搜索卡片文件，标签以冒号包裹形式存储在 Org 属性中。"""
    if not args.tags:
        die("用法: kb tags <标签> [标签2 ...]")

    json_items: list[dict] = []

    for tag in args.tags:
        if shutil.which("rg"):
            result = subprocess.run(
                ["rg", "--color=never", "-l", f":{tag}:", str(KB_EXPERIENCES)],
                capture_output=True,
                text=True,
            )
        else:
            result = subprocess.run(
                ["grep", "-rl", f":{tag}:", str(KB_EXPERIENCES)],
                capture_output=True,
                text=True,
            )
        files = (
            [Path(line) for line in result.stdout.splitlines() if line]
            if result.returncode == 0 and result.stdout.strip()
            else []
        )

        if args.json:
            for filepath in files:
                try:
                    content = filepath.read_text(encoding="utf-8")
                except OSError:
                    continue
                card_id = parse_org_prop(content, "ID") or filepath.stem.split("-")[0]
                json_items.append(
                    {
                        "tag": tag,
                        "id": card_id,
                        "title": read_org_title(content),
                    }
                )
            continue

        print(f"── 标签: {tag} ──")
        if files:
            for filepath in files:
                print(filepath)
        else:
            print("  (无匹配)")

    if args.json:
        print(json.dumps(json_items, ensure_ascii=False, indent=2))


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: stats — 知识库统计
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_stats(args: argparse.Namespace) -> None:
    """输出知识库的统计概览。"""
    ensure_dirs()
    index = _load_index()
    cards = index["cards"]
    total = len(cards)

    cat_counter: Counter = Counter()
    type_counter: Counter = Counter()
    owner_counter: Counter = Counter()
    tech_counter: Counter = Counter()
    dates = []

    for c in cards:
        cat_counter[c.get("category", "unknown")] += 1
        type_counter[c.get("type", "unknown")] += 1
        owner_counter[c.get("owner", "unknown")] += 1
        tech_counter[c.get("tech", "unknown")] += 1
        if c.get("created"):
            dates.append(c["created"])

    print(f"═══ 知识库统计 ═══")
    print(f"总卡片数: {total}")
    if dates:
        print(f"时间范围: {min(dates)} ~ {max(dates)}")
    print()

    for label, counter in [
        ("按类别", cat_counter),
        ("按类型", type_counter),
        ("按执行者", owner_counter),
        ("按技术栈", tech_counter),
    ]:
        print(f"── {label} ──")
        for k, v in counter.most_common():
            bar = "█" * v
            print(f"  {k:20s} {v:3d} {bar}")
        print()

    # MEMORY 章节已废弃，偏好/项目上下文由 Hermes memory 工具管理
    # 本命令不再输出 MEMORY 统计


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: health — 知识库健康度报告
# ═══════════════════════════════════════════════════════════════════════════════

def cmd_health(args: argparse.Namespace) -> None:
    """输出知识库健康度报告（只读诊断）。"""
    ensure_dirs()
    index = _load_index()
    cards = index["cards"]
    total = len(cards)

    status_counts = Counter(c.get("status", "done") for c in cards)
    done = status_counts.get("done", 0)
    stable = status_counts.get("stable", 0)
    stale = status_counts.get("stale", 0)
    archived = status_counts.get("archived", 0)

    print("=== 知识库健康度报告 ===")
    print(
        f"总卡片: {total} | done: {done} | stable: {stable} | stale: {stale} | archived: {archived}"
    )
    print()

    # 孤立率
    linked_cards = set()
    for f in KB_EXPERIENCES.rglob("*.org"):
        if f.is_symlink():
            continue
        content = f.read_text(encoding="utf-8")
        if "[[file:" in content:
            linked_cards.add(parse_org_prop(content, "ID") or f.stem.split("-")[0])
    isolated = total - len(linked_cards)
    isolated_pct = (isolated / total * 100) if total > 0 else 0
    isolated_icon = "✅" if isolated_pct < 15 else "⚠️" if isolated_pct < 25 else "❌"

    stale_pct = (stale / total * 100) if total > 0 else 0
    stale_icon = "✅" if stale_pct < 10 else "⚠️" if stale_pct < 20 else "❌"

    type_counts = Counter(c.get("type", "unknown") for c in cards)
    max_type, max_type_count = (
        type_counts.most_common(1)[0] if type_counts else ("none", 0)
    )
    max_type_pct = (max_type_count / total * 100) if total > 0 else 0
    type_icon = "✅" if max_type_pct < 45 else "⚠️"

    cat_counts = Counter(c.get("category", "unknown") for c in cards)
    weak_cats = [(cat, cnt) for cat, cnt in cat_counts.items() if cnt < 3]

    print("── 健康指标 ──")
    print(f"  孤立率:     {isolated_pct:.0f}% [阈值 <15%] {isolated_icon}")
    print(f"  过时率:      {stale_pct:.0f}% [阈值 <10%] {stale_icon}")
    print(f"  类型偏斜:   {max_type} {max_type_pct:.0f}% [阈值 <45%] {type_icon}")
    if weak_cats:
        cats_str = ", ".join(f"{cat}({cnt})" for cat, cnt in weak_cats)
        print(f"  薄弱类别:   {cats_str} [阈值 ≥3] ❌")
    else:
        print(f"  薄弱类别:   无 [阈值 ≥3] ✅")

    # MEMORY 章节已废弃，偏好/项目上下文由 Hermes memory 工具管理
    # 本命令不再输出 MEMORY 健康指标
