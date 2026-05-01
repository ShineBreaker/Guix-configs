#!/usr/bin/env python3
"""知识空白检测 — 交叉分析类别×类型，识别缺失组合、逾期卡片、薄弱领域。

用法：
    python3 find_gaps.py [--dir DIR] [--json] [--stale-days 90]

输出：
    --json         以 JSON 格式输出
    --stale-days   超过 N 天未更新的卡片视为陈旧（默认 90）
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# 所有合法取值（与 kb 工具参数一致）
ALL_CATEGORIES = {
    "emacs", "python", "rust", "go", "android", "scheme",
    "shell", "nix", "guix", "web", "general",
}
ALL_TYPES = {"debug", "refactor", "research", "workflow", "feature", "config"}


def parse_org_metadata(filepath: str) -> dict | None:
    meta = {"file": filepath}
    try:
        with open(filepath) as f:
            content = f.read()
    except Exception:
        return None

    props_match = re.search(r":PROPERTIES:(.*?):END:", content, re.DOTALL)
    if not props_match:
        return None

    props = props_match.group(1)

    def get_prop(key):
        m = re.search(rf":{key}:\s*(.+)", props)
        return m.group(1).strip() if m else None

    meta["category"] = get_prop("CATEGORY") or "unknown"
    meta["type"] = get_prop("TYPE") or "unknown"
    meta["tech"] = get_prop("TECH") or ""
    meta["created"] = get_prop("CREATED")
    meta["owner"] = get_prop("OWNER") or "unknown"

    title_match = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    meta["title"] = title_match.group(1).strip() if title_match else "unknown"

    return meta


def parse_date(date_str: str | None) -> datetime | None:
    if not date_str:
        return None
    m = re.search(r"(\d{4}-\d{2}-\d{2})", date_str)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d")
        except ValueError:
            pass
    return None


def find_gaps(experiences_dir: str, stale_days: int = 90) -> dict:
    exp_path = Path(experiences_dir)
    if not exp_path.is_dir():
        return {"error": f"目录不存在: {experiences_dir}"}

    entries = []
    for f in sorted(exp_path.glob("*.org")):
        meta = parse_org_metadata(str(f))
        if meta:
            entries.append(meta)

    # 实际覆盖
    covered = defaultdict(set)  # category -> {types}
    owner_coverage = defaultdict(set)  # category -> {owners}
    category_counts = defaultdict(int)

    for e in entries:
        covered[e["category"]].add(e["type"])
        owner_coverage[e["category"]].add(e["owner"])
        category_counts[e["category"]] += 1

    # 缺失组合
    missing_combos = []
    for cat in ALL_CATEGORIES:
        for typ in ALL_TYPES:
            if typ not in covered.get(cat, set()):
                missing_combos.append({"category": cat, "type": typ})

    # 薄弱领域（卡片数 ≤ 2 的类别）
    weak_categories = [
        {"category": cat, "count": count}
        for cat, count in sorted(category_counts.items(), key=lambda x: x[1])
        if count <= 2
    ]

    # 陈旧卡片
    now = datetime.now()
    stale_cards = []
    for e in entries:
        d = parse_date(e.get("created"))
        if d and (now - d).days > stale_days:
            stale_cards.append({
                "file": os.path.basename(e["file"]),
                "title": e["title"],
                "category": e["category"],
                "created": e["created"],
                "days_old": (now - d).days,
            })

    # 无 human 参与的类别（纯 AI 知识，可能缺少人类视角）
    ai_only_categories = [
        cat for cat, owners in owner_coverage.items()
        if "human" not in owners and "collaborative" not in owners and cat in ALL_CATEGORIES
    ]

    result = {
        "missing_category_type_combos": missing_combos,
        "missing_count": len(missing_combos),
        "weak_categories": weak_categories,
        "stale_cards": stale_cards,
        "stale_count": len(stale_cards),
        "ai_only_categories": ai_only_categories,
        "all_categories": sorted(ALL_CATEGORIES),
        "all_types": sorted(ALL_TYPES),
        "active_categories": sorted(category_counts.keys()),
    }

    return result


def main():
    parser = argparse.ArgumentParser(description="知识空白检测")
    parser.add_argument("--dir", default=os.path.expanduser("~/Documents/Org/experiences"),
                        help="经验卡片目录")
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--stale-days", type=int, default=90, help="陈旧阈值（天）")
    args = parser.parse_args()

    result = find_gaps(args.dir, stale_days=args.stale_days)

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if "error" in result:
            print(f"错误: {result['error']}")
            sys.exit(1)
        print("=== 知识空白报告 ===\n")

        if result["missing_count"] > 0:
            print(f"⚠ 缺失的类别×类型组合 ({result['missing_count']} 项):")
            # 按类别分组
            by_cat = defaultdict(list)
            for combo in result["missing_category_type_combos"]:
                by_cat[combo["category"]].append(combo["type"])
            for cat in sorted(by_cat.keys()):
                if cat in result["active_categories"]:
                    print(f"  [{cat}] 缺: {', '.join(by_cat[cat])}")
                else:
                    print(f"  [{cat}] 整类空白 — 缺: {', '.join(by_cat[cat])}")
            # 未出现的类别
            missing_cats = set(result["all_categories"]) - set(result["active_categories"])
            if missing_cats:
                print(f"\n  完全空白的类别: {', '.join(sorted(missing_cats))}")
        else:
            print("✅ 类别×类型全覆盖")

        if result["weak_categories"]:
            print(f"\n⚠ 薄弱领域 (卡片数 ≤ 2):")
            for wc in result["weak_categories"]:
                print(f"  {wc['category']}: 仅 {wc['count']} 张卡片")

        if result["stale_count"] > 0:
            print(f"\n⚠ 陈旧卡片 (>{args.stale_days}天, 共 {result['stale_count']} 张):")
            for card in sorted(result["stale_cards"], key=lambda x: x["days_old"], reverse=True):
                print(f"  {card['file']} [{card['category']}] {card['days_old']}天前 — {card['title'][:60]}")

        if result["ai_only_categories"]:
            print(f"\n⚠ 纯 AI 无人类参与的类别:")
            for cat in result["ai_only_categories"]:
                print(f"  {cat}")


if __name__ == "__main__":
    main()
