#!/usr/bin/env python3
"""知识库健康分析 — 统计类别/类型分布、检测重复、评估卡片质量。

用法：
    python3 analyze_kb.py [--dir DIR] [--json] [--duplicates] [--quality]

输出：
    --json    以 JSON 格式输出
    --duplicates  检测疑似重复卡片
    --quality     检测质量问题（空章节、缺元数据等）
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path


def parse_org_metadata(filepath: str) -> dict | None:
    """从 Org 文件头部提取元数据。"""
    meta = {"file": filepath, "quality_issues": []}
    try:
        with open(filepath) as f:
            content = f.read()
    except Exception:
        return None

    # 提取 PROPERTIES 块
    props_match = re.search(r":PROPERTIES:(.*?):END:", content, re.DOTALL)
    if not props_match:
        meta["quality_issues"].append("missing_properties")
        # 仍然尝试提取标题
        title_match = re.search(r"^\* DONE (.+)", content, re.MULTILINE)
        meta["title"] = title_match.group(1).strip() if title_match else "unknown"
        return meta

    props = props_match.group(1)

    def get_prop(key):
        m = re.search(rf":{key}:\s*(.+)", props)
        return m.group(1).strip() if m else None

    meta["id"] = get_prop("ID")
    meta["created"] = get_prop("CREATED")
    meta["category"] = get_prop("CATEGORY") or "unknown"
    meta["tech"] = get_prop("TECH") or ""
    meta["type"] = get_prop("TYPE") or "unknown"
    meta["status"] = get_prop("STATUS") or "unknown"
    meta["owner"] = get_prop("OWNER") or "unknown"

    # 提取标题
    title_match = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    meta["title"] = title_match.group(1).strip() if title_match else "unknown"

    # 质量检查
    if not meta["id"]:
        meta["quality_issues"].append("missing_id")
    if not meta["created"]:
        meta["quality_issues"].append("missing_created")
    if meta["category"] == "unknown":
        meta["quality_issues"].append("missing_category")
    if not meta["tech"]:
        meta["quality_issues"].append("missing_tech")

    # 检查章节完整性
    has_task_desc = bool(re.search(r"^\*\* 任务描述", content, re.MULTILINE))
    has_execution = bool(re.search(r"^\*\* 执行过程", content, re.MULTILINE))
    has_findings = bool(
        re.search(r"^\*{2,3} (关键发现|难点与坑点|经验教训)", content, re.MULTILINE)
    )

    if not has_task_desc:
        meta["quality_issues"].append("missing_task_description")
    if not has_execution:
        meta["quality_issues"].append("missing_execution_process")
    if not has_findings:
        meta["quality_issues"].append("missing_findings")

    # 检查 Markdown 格式污染
    if "```" in content:
        meta["quality_issues"].append("markdown_code_blocks")
    if re.search(r"(?<!\*)\*\*(?!\*)", content) and "** " not in content:
        meta["quality_issues"].append("markdown_bold")

    # 统计内容长度
    meta["line_count"] = len(content.splitlines())

    return meta


def parse_date(date_str: str | None) -> datetime | None:
    """解析 Org 日期字符串。"""
    if not date_str:
        return None
    # 格式: [2026-04-23 四 23:02] 或 [2026-04-23 四]
    m = re.search(r"(\d{4}-\d{2}-\d{2})", date_str)
    if m:
        try:
            return datetime.strptime(m.group(1), "%Y-%m-%d")
        except ValueError:
            pass
    return None


def detect_duplicates(entries: list[dict]) -> list[dict]:
    """检测疑似重复卡片（标题相似度）。"""
    duplicates = []
    for i, a in enumerate(entries):
        for b in entries[i + 1 :]:
            # 简单关键词重叠检测
            a_words = set(re.findall(r"\w+", a["title"].lower()))
            b_words = set(re.findall(r"\w+", b["title"].lower()))
            if not a_words or not b_words:
                continue
            overlap = len(a_words & b_words) / min(len(a_words), len(b_words))
            # 80% 以上重叠且同类别视为疑似重复
            if overlap > 0.8 and a["category"] == b["category"]:
                duplicates.append(
                    {
                        "card_a": os.path.basename(a["file"]),
                        "title_a": a["title"],
                        "card_b": os.path.basename(b["file"]),
                        "title_b": b["title"],
                        "overlap": round(overlap, 2),
                        "category": a["category"],
                    }
                )
    return duplicates


def analyze(
    experiences_dir: str, check_duplicates: bool = False, check_quality: bool = False
) -> dict:
    """主分析函数。"""
    exp_path = Path(experiences_dir)
    if not exp_path.is_dir():
        return {"error": f"目录不存在: {experiences_dir}"}

    entries = []
    for f in sorted(exp_path.glob("*.org")):
        meta = parse_org_metadata(str(f))
        if meta:
            entries.append(meta)

    # 基础统计
    category_dist = Counter(e["category"] for e in entries)
    type_dist = Counter(e["type"] for e in entries)
    owner_dist = Counter(e["owner"] for e in entries)

    # 时间分布
    dates = [parse_date(e.get("created")) for e in entries]
    dates = [d for d in dates if d]
    recent_7d = sum(1 for d in dates if (datetime.now() - d).days <= 7)
    recent_30d = sum(1 for d in dates if (datetime.now() - d).days <= 30)

    # 类别×类型交叉
    cross_dist = defaultdict(lambda: defaultdict(int))
    for e in entries:
        cross_dist[e["category"]][e["type"]] += 1

    result = {
        "total_cards": len(entries),
        "category_distribution": dict(category_dist.most_common()),
        "type_distribution": dict(type_dist.most_common()),
        "owner_distribution": dict(owner_dist.most_common()),
        "recent_7d": recent_7d,
        "recent_30d": recent_30d,
        "category_type_matrix": {cat: dict(types) for cat, types in cross_dist.items()},
    }

    # 内容长度分布
    line_counts = [e["line_count"] for e in entries]
    if line_counts:
        result["avg_lines"] = round(sum(line_counts) / len(line_counts), 1)
        result["min_lines"] = min(line_counts)
        result["max_lines"] = max(line_counts)

    # 重复检测
    if check_duplicates:
        result["potential_duplicates"] = detect_duplicates(entries)

    # 质量检查
    if check_quality:
        quality_stats = Counter()
        problem_cards = []
        for e in entries:
            for issue in e["quality_issues"]:
                quality_stats[issue] += 1
            if e["quality_issues"]:
                problem_cards.append(
                    {
                        "file": os.path.basename(e["file"]),
                        "title": e["title"],
                        "issues": e["quality_issues"],
                    }
                )
        result["quality_issues"] = dict(quality_stats.most_common())
        result["problem_cards"] = problem_cards

    return result


def main():
    parser = argparse.ArgumentParser(description="知识库健康分析")
    parser.add_argument(
        "--dir",
        default=os.path.expanduser("~/Documents/Org/experiences"),
        help="经验卡片目录",
    )
    parser.add_argument("--json", action="store_true", help="JSON 格式输出")
    parser.add_argument("--duplicates", action="store_true", help="检测疑似重复")
    parser.add_argument("--quality", action="store_true", help="检测质量问题")
    args = parser.parse_args()

    result = analyze(
        args.dir, check_duplicates=args.duplicates, check_quality=args.quality
    )

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        if "error" in result:
            print(f"错误: {result['error']}")
            sys.exit(1)
        print(f"=== 知识库健康报告 ===")
        print(f"总卡片数: {result['total_cards']}")
        print(f"近7天新增: {result.get('recent_7d', 0)}")
        print(f"近30天新增: {result.get('recent_30d', 0)}")
        if "avg_lines" in result:
            print(
                f"内容长度: 平均 {result['avg_lines']} 行 (最短 {result['min_lines']}, 最长 {result['max_lines']})"
            )

        print(f"\n类别分布:")
        for cat, count in result["category_distribution"].items():
            bar = "█" * count
            print(f"  {cat:15s} {count:3d} {bar}")

        print(f"\n类型分布:")
        for typ, count in result["type_distribution"].items():
            bar = "█" * count
            print(f"  {typ:15s} {count:3d} {bar}")

        print(f"\n类别×类型矩阵:")
        header = f"{'':15s}" + "".join(
            f"{t:>10s}" for t in sorted(result["type_distribution"].keys())
        )
        print(header)
        for cat in sorted(result["category_type_matrix"].keys()):
            row = f"{cat:15s}"
            for typ in sorted(result["type_distribution"].keys()):
                row += f"{result['category_type_matrix'][cat].get(typ, 0):>10d}"
            print(row)

        if result.get("potential_duplicates"):
            print(f"\n⚠ 疑似重复 ({len(result['potential_duplicates'])} 对):")
            for d in result["potential_duplicates"]:
                print(
                    f"  [{d['category']}] {d['card_a']} ≈ {d['card_b']} (重叠率: {d['overlap']})"
                )

        if result.get("quality_issues"):
            print(f"\n⚠  质量问题:")
            for issue, count in result["quality_issues"].items():
                print(f"  {issue}: {count} 张卡片")
            print(f"\n  问题卡片清单:")
            for card in result.get("problem_cards", []):
                print(f"  - {card['file']}: {', '.join(card['issues'])}")


if __name__ == "__main__":
    main()
