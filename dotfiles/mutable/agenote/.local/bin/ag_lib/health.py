#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""ag_lib.health — 知识库健康度分析的统一真相源。

合并自原三套实现（cards.cmd_health / agenote_mcp.agenote_health / 策展脚本
analyze_kb+find_gaps），提供结构化的健康数据供 CLI、MCP、viz 复用。

分层：
  - _compute_base_metrics : 基础健康率（孤立/过时/类型偏斜/薄弱类别），读 index.json
  - analyze               : 分布/矩阵/近期/质量/重复，可逐文件扫描（check_quality 时）
  - find_gaps             : 缺失组合/陈旧卡片(时间维)/纯AI类别
  - cmd_health/cmd_gaps   : CLI 入口（print 人类可读报告）
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

from ag_lib.cards import _jaccard_similarity
from ag_lib.core import (
    STALE_DAYS,
    VALID_TYPES,
    _card_dict,
    _load_index,
    default_context,
    ensure_dirs,
    parse_org_prop,
    read_org_title,
)

# 卡片陈旧阈值（时间维度）。区别于 core.STALE_DAYS（=30，memory 语义）。
CARD_STALE_DAYS = 90


# ═══════════════════════════════════════════════════════════════════════════════
# 工具
# ═══════════════════════════════════════════════════════════════════════════════


def _status(pct: float, ok_max: float, warn_max: float) -> str:
    """三级分级：ok / warn / bad。"""
    if pct < ok_max:
        return "ok"
    if pct < warn_max:
        return "warn"
    return "bad"


def _icon(status: str) -> str:
    return {"ok": "✅", "warn": "⚠️", "bad": "❌"}.get(status, "")


def _parse_date(date_str: str | None) -> datetime | None:
    """解析 Org 日期串（如 [2026-04-23 四 23:02]）→ datetime。

    迁自 kb_org_utils.parse_date；core._card_dict 只做 re.sub 去括号不转 datetime。
    """
    if not date_str:
        return None
    m = re.search(r"(\d{4}-\d{2}-\d{2})", date_str)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d")
        except ValueError:
            pass
    return None


def _quality_issues(content: str) -> list[str]:
    """对单张卡片正文做质量检查，返回问题标签列表。

    迁自 kb_org_utils.parse_org_metadata(quality_check=True) 的质量部分；
    PROPERTIES/标题解析已改用 core.parse_org_prop/read_org_title，不在此重复。
    """
    issues: list[str] = []
    if not parse_org_prop(content, "ID"):
        issues.append("missing_id")
    if not parse_org_prop(content, "CREATED"):
        issues.append("missing_created")
    if not parse_org_prop(content, "CATEGORY"):
        issues.append("missing_category")
    if not parse_org_prop(content, "TECH"):
        issues.append("missing_tech")

    # 章节完整性
    if not re.search(r"^\*\* 任务描述", content, re.MULTILINE):
        issues.append("missing_task_description")
    if not re.search(r"^\*\* 执行过程", content, re.MULTILINE):
        issues.append("missing_execution_process")
    if not re.search(r"^\*{2,3} (关键发现|难点与坑点|经验教训)", content, re.MULTILINE):
        issues.append("missing_findings")

    # Markdown 格式污染
    if "```" in content:
        issues.append("markdown_code_blocks")
    if re.search(r"(?<!\*)\*\*(?!\*)", content) and "** " not in content:
        issues.append("markdown_bold")

    return issues


# ═══════════════════════════════════════════════════════════════════════════════
# 基础健康率（cmd_health + agenote_health 的公共逻辑）
# ═══════════════════════════════════════════════════════════════════════════════


def _compute_base_metrics(ctx=None) -> dict:
    """基础健康指标：状态分布、孤立率、过时率、类型偏斜、薄弱类别。

    数据源：_load_index(ctx)（快），孤立率需扫 experiences/ 正文找 [[file: 链接。
    合并自 cards.cmd_health(1141) 与 agenote_mcp.agenote_health(480) 的重复逻辑。
    """
    ctx = ctx or default_context()
    ensure_dirs(ctx)
    index = _load_index(ctx)
    cards = index["cards"]
    total = len(cards)

    status_counts = Counter(c.get("status", "done") for c in cards)

    # 孤立率：无 [[file: 或 [[id: 链接的卡片占比
    # 两种链接都算「被引用」：[[file:foo.org]] 是传统的 wikilink，
    # [[id:20260101-xxxxxx]] 是 card ID 直接引用（双向链接，避免
    # 每次添加 reference 都要找完整路径）。两者都应被视为非孤立。
    linked_cards = set()
    for f in ctx.experiences.rglob("*.org"):
        if f.is_symlink():
            continue
        content = f.read_text(encoding="utf-8")
        if "[[file:" in content or "[[id:" in content:
            linked_cards.add(parse_org_prop(content, "ID") or f.stem.split("-")[0])
    isolated = total - len(linked_cards)
    isolated_pct = round(isolated / total * 100) if total > 0 else 0

    # 过时率（status 维度）
    stale = status_counts.get("stale", 0)
    stale_pct = round(stale / total * 100) if total > 0 else 0

    # 类型偏斜
    type_counts = Counter(c.get("type", "unknown") for c in cards)
    max_type, max_type_count = (
        type_counts.most_common(1)[0] if type_counts else ("none", 0)
    )
    max_type_pct = round(max_type_count / total * 100) if total > 0 else 0

    # 薄弱类别
    cat_counts = Counter(c.get("category", "unknown") for c in cards)
    weak_cats = {cat: cnt for cat, cnt in cat_counts.items() if cnt < 3}

    # MEMORY 统计（feedback / project）
    memory_stats = _memory_stats(ctx)

    return {
        "total": total,
        "status": dict(status_counts),
        "isolated": {
            "pct": isolated_pct,
            "count": isolated,
            "threshold": 15,
            "status": _status(isolated_pct, 15, 25),
        },
        "stale": {
            "pct": stale_pct,
            "count": stale,
            "threshold": 10,
            "status": _status(stale_pct, 10, 20),
        },
        "type_skew": {
            "type": max_type,
            "pct": max_type_pct,
            "count": max_type_count,
            "threshold": 45,
            "status": _status(max_type_pct, 45, 60),
        },
        "weak_categories": weak_cats,
        "memory": memory_stats,
    }


def _memory_stats(ctx) -> dict:
    """MEMORY.org 的 feedback/project 计数。迁自 cmd_health 的 MEMORY 段。"""
    mem_path = getattr(ctx, "memory_org", None)
    if not mem_path or not mem_path.exists():
        return {"feedback": 0, "stale_feedback": 0, "project": 0}
    mem_text = mem_path.read_text(encoding="utf-8")
    fb_count = len(re.findall(r"^\*\* F\d+", mem_text, re.MULTILINE))
    stale_fb = 0
    for m in re.finditer(r":UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", mem_text):
        try:
            updated = datetime.strptime(m.group(1), "%Y-%m-%d")
            if (datetime.now() - updated).days > STALE_DAYS:
                stale_fb += 1
        except ValueError:
            pass
    proj_section = ""
    if "* project" in mem_text and "* reference" in mem_text:
        ps, pe = mem_text.find("* project"), mem_text.find("* reference")
        if ps < pe:
            proj_section = mem_text[ps:pe]
    proj_count = len(
        re.findall(r"^\*\* .+\n\s+:PROPERTIES:", proj_section, re.MULTILINE)
    )
    return {"feedback": fb_count, "stale_feedback": stale_fb, "project": proj_count}


# ═══════════════════════════════════════════════════════════════════════════════
# 深度分析（迁自 analyze_kb.py）
# ═══════════════════════════════════════════════════════════════════════════════


def analyze(
    ctx=None, check_duplicates: bool = False, check_quality: bool = False
) -> dict:
    """分布 / 时间 / 类别×类型矩阵 / 内容长度 / 质量 / 重复。

    分布与矩阵走 index.json（快）；check_quality 时逐文件读正文做质量扫描（准）。
    detect_duplicates 删除，复用 cards._jaccard_similarity（统一 Jaccard 算法）。
    """
    ctx = ctx or default_context()
    ensure_dirs(ctx)
    index = _load_index(ctx)
    cards = [c for c in index["cards"] if c.get("status") != "archived"]

    category_dist = Counter(c.get("category", "unknown") for c in cards)
    type_dist = Counter(c.get("type", "unknown") for c in cards)
    owner_dist = Counter(c.get("owner", "unknown") for c in cards)

    # 时间分布
    dates = [_parse_date(c.get("created")) for c in cards]
    dates = [d for d in dates if d]
    now = datetime.now()
    recent_7d = sum(1 for d in dates if (now - d).days <= 7)
    recent_30d = sum(1 for d in dates if (now - d).days <= 30)

    # 类别×类型交叉矩阵
    cross_dist = defaultdict(lambda: defaultdict(int))
    for c in cards:
        cross_dist[c.get("category", "unknown")][c.get("type", "unknown")] += 1

    result = {
        "total_cards": len(cards),
        "category_distribution": dict(category_dist.most_common()),
        "type_distribution": dict(type_dist.most_common()),
        "owner_distribution": dict(owner_dist.most_common()),
        "recent_7d": recent_7d,
        "recent_30d": recent_30d,
        "category_type_matrix": {cat: dict(types) for cat, types in cross_dist.items()},
    }

    # 重复检测（复用 cards 的 Jaccard + category/tech 加权）
    if check_duplicates:
        result["potential_duplicates"] = _detect_duplicates(cards)

    # 质量检查（需逐文件读正文）
    if check_quality:
        result.update(_quality_scan(ctx))

    return result


def _detect_duplicates(cards: list[dict], threshold: float = 0.7) -> list[dict]:
    """疑似重复卡片对。复用 cards._jaccard_similarity + category/tech 加权。"""
    pairs = []
    for i in range(len(cards)):
        for j in range(i + 1, len(cards)):
            a, b = cards[i], cards[j]
            sim = _jaccard_similarity(a.get("title", ""), b.get("title", ""))
            if a.get("category") == b.get("category"):
                sim += 0.15
            if a.get("tech") and a.get("tech") == b.get("tech"):
                sim += 0.1
            sim = min(sim, 1.0)
            if sim >= threshold:
                pairs.append(
                    {
                        "id_a": a["id"],
                        "title_a": a.get("title", "")[:60],
                        "id_b": b["id"],
                        "title_b": b.get("title", "")[:60],
                        "similarity": round(sim, 2),
                        "category": a.get("category", "unknown"),
                    }
                )
    return pairs


def _quality_scan(ctx) -> dict:
    """逐文件扫描质量（章节完整性/元数据缺失/Markdown 污染/行数）。"""
    quality_stats = Counter()
    problem_cards = []
    line_counts = []
    for f in sorted(ctx.experiences.rglob("*.org")):
        if f.is_symlink():
            continue
        content = f.read_text(encoding="utf-8")
        issues = _quality_issues(content)
        line_counts.append(len(content.splitlines()))
        for issue in issues:
            quality_stats[issue] += 1
        if issues:
            problem_cards.append(
                {
                    "file": f.name,
                    "id": parse_org_prop(content, "ID") or f.stem,
                    "title": read_org_title(content),
                    "issues": issues,
                }
            )
    result = {
        "quality_issues": dict(quality_stats.most_common()),
        "problem_cards": problem_cards,
    }
    if line_counts:
        result["avg_lines"] = round(sum(line_counts) / len(line_counts), 1)
        result["min_lines"] = min(line_counts)
        result["max_lines"] = max(line_counts)
    return result


# ═══════════════════════════════════════════════════════════════════════════════
# 空白检测（迁自 find_gaps.py）
# ═══════════════════════════════════════════════════════════════════════════════


def find_gaps(ctx=None, stale_days: int = CARD_STALE_DAYS) -> dict:
    """缺失组合 / 陈旧卡片(时间维) / 薄弱类别 / 纯AI类别。

    ALL_TYPES 复用 core.VALID_TYPES（原 find_gaps 硬编码已删除）。
    """
    ctx = ctx or default_context()
    ensure_dirs(ctx)
    index = _load_index(ctx)
    cards = [c for c in index["cards"] if c.get("status") != "archived"]

    covered = defaultdict(set)  # category -> {types}
    owner_coverage = defaultdict(set)  # category -> {owners}
    category_counts = defaultdict(int)

    for c in cards:
        covered[c.get("category", "unknown")].add(c.get("type", "unknown"))
        owner_coverage[c.get("category", "unknown")].add(c.get("owner", "unknown"))
        category_counts[c.get("category", "unknown")] += 1

    # 缺失组合：已有 category × 全部 type（VALID_TYPES）的覆盖缺口
    missing_combos = []
    for cat in sorted(category_counts.keys()):
        for typ in VALID_TYPES:
            if typ not in covered.get(cat, set()):
                missing_combos.append({"category": cat, "type": typ})

    # 薄弱类别（≤2 张）
    weak_categories = [
        {"category": cat, "count": cnt}
        for cat, cnt in sorted(category_counts.items(), key=lambda x: x[1])
        if cnt <= 2
    ]

    # 陈旧卡片（时间维度，区别于 base_metrics 的 status 维度）
    now = datetime.now()
    stale_cards = []
    for c in cards:
        d = _parse_date(c.get("created"))
        if d and (now - d).days > stale_days:
            stale_cards.append(
                {
                    "id": c["id"],
                    "file": c.get("file", ""),
                    "title": c.get("title", "")[:60],
                    "category": c.get("category", "unknown"),
                    "created": c.get("created", ""),
                    "days_old": (now - d).days,
                }
            )
    stale_cards.sort(key=lambda x: x["days_old"], reverse=True)

    # 纯 AI 无人类参与的类别
    ai_only_categories = [
        cat
        for cat, owners in owner_coverage.items()
        if "human" not in owners and "collaborative" not in owners
    ]

    return {
        "missing_category_type_combos": missing_combos,
        "missing_count": len(missing_combos),
        "weak_categories": weak_categories,
        "stale_cards": stale_cards,
        "stale_count": len(stale_cards),
        "ai_only_categories": sorted(ai_only_categories),
        "all_types": sorted(VALID_TYPES),
        "active_categories": sorted(category_counts.keys()),
    }


# ═══════════════════════════════════════════════════════════════════════════════
# CLI 入口
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_health(args: argparse.Namespace, ctx=None) -> None:
    """kb health / agenote health：人类可读健康度报告（含分布与矩阵）。"""
    ctx = ctx or default_context()
    base = _compute_base_metrics(ctx)
    deep = analyze(
        ctx,
        check_duplicates=getattr(args, "duplicates", False),
        check_quality=getattr(args, "quality", False),
    )

    print("=== 知识库健康度报告 ===")
    print(
        f"总卡片: {base['total']} | "
        f"done: {base['status'].get('done', 0)} | "
        f"stable: {base['status'].get('stable', 0)} | "
        f"stale: {base['status'].get('stale', 0)} | "
        f"archived: {base['status'].get('archived', 0)}"
    )
    print()

    print("── 健康指标 ──")
    iso = base["isolated"]
    print(f"  孤立率:   {iso['pct']}% [阈值 <15%] {_icon(iso['status'])}")
    st = base["stale"]
    print(f"  过时率:   {st['pct']}% [阈值 <10%] {_icon(st['status'])}")
    ts = base["type_skew"]
    print(f"  类型偏斜: {ts['type']} {ts['pct']}% [阈值 <45%] {_icon(ts['status'])}")
    if base["weak_categories"]:
        cats = ", ".join(f"{c}({n})" for c, n in base["weak_categories"].items())
        print(f"  薄弱类别: {cats} [阈值 ≥3] ❌")
    else:
        print(f"  薄弱类别: 无 [阈值 ≥3] ✅")

    print()
    print(f"── 分布 ──")
    print(f"  近7天: {deep['recent_7d']} | 近30天: {deep['recent_30d']}")
    if "avg_lines" in deep:
        print(
            f"  内容长度: 平均 {deep['avg_lines']} 行 (最短 {deep['min_lines']}, 最长 {deep['max_lines']})"
        )
    print(
        f"  类别: {', '.join(f'{c}({n})' for c, n in deep['category_distribution'].items())}"
    )
    print(
        f"  类型: {', '.join(f'{t}({n})' for t, n in deep['type_distribution'].items())}"
    )

    if deep.get("potential_duplicates"):
        print(f"\n── 疑似重复 ({len(deep['potential_duplicates'])} 对) ──")
        for d in deep["potential_duplicates"]:
            print(f"  [{d['similarity']:.0%}] {d['id_a']}: {d['title_a']}")
            print(f"          {d['id_b']}: {d['title_b']}")

    if deep.get("quality_issues"):
        print(f"\n── 质量问题 ──")
        for issue, cnt in deep["quality_issues"].items():
            print(f"  {issue}: {cnt} 张")

    mem = base["memory"]
    if mem["feedback"] or mem["project"]:
        print()
        print("── 记忆 ──")
        print(f"  feedback: {mem['feedback']} (stale: {mem['stale_feedback']})")
        print(f"  project:  {mem['project']}")


def cmd_gaps(args: argparse.Namespace, ctx=None) -> None:
    """kb gaps / agenote gaps：知识空白报告。"""
    ctx = ctx or default_context()
    stale_days = getattr(args, "stale_days", CARD_STALE_DAYS)
    if getattr(args, "json", False):
        print(
            json.dumps(
                find_gaps(ctx, stale_days=stale_days), ensure_ascii=False, indent=2
            )
        )
        return

    result = find_gaps(ctx, stale_days=stale_days)
    print("=== 知识空白报告 ===\n")

    if result["missing_count"] > 0:
        print(f"⚠ 缺失的类别×类型组合 ({result['missing_count']} 项):")
        by_cat = defaultdict(list)
        for combo in result["missing_category_type_combos"]:
            by_cat[combo["category"]].append(combo["type"])
        for cat in sorted(by_cat.keys()):
            print(f"  [{cat}] 缺: {', '.join(by_cat[cat])}")
    else:
        print("✅ 类别×类型全覆盖")

    if result["weak_categories"]:
        print(f"\n⚠ 薄弱领域 (卡片数 ≤ 2):")
        for wc in result["weak_categories"]:
            print(f"  {wc['category']}: 仅 {wc['count']} 张卡片")

    if result["stale_count"] > 0:
        print(f"\n⚠ 陈旧卡片 (>{stale_days}天, 共 {result['stale_count']} 张):")
        for card in result["stale_cards"]:
            print(
                f"  {card['id']} [{card['category']}] {card['days_old']}天前 — {card['title']}"
            )

    if result["ai_only_categories"]:
        print(f"\n⚠ 纯 AI 无人类参与的类别:")
        for cat in result["ai_only_categories"]:
            print(f"  {cat}")
