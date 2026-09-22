#!/usr/bin/env python3
"""把 jev 选中的推文导出成供 LLM 加工的原始素材。

用法:
    digest_build.py build --state-dir DIR [--date YYYY-MM-DD] [--top N]

输入: <state>/picked/YYYY-MM-DD.json（jev_score.py 产出，已按综合分降序）
输出: stdout 打印素材 markdown，含作者、时间、原文、热度量级。

本脚本只把筛选结果整理成干净素材。翻译、摘要、分组、加要闻由
cron job 的 LLM 完成，规则写在 cron prompt 里。
空结果时明确说"今日无值得关注的内容"，绝不编造条目。

"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path


def build_md(picked: list[dict], date: str, top: int) -> str:
    total = len(picked)
    if not total:
        return (f"# X 关注的每日摘要 · {date}\n\n"
                f"今日没有推文通过筛选，没有值得关注的内容。")

    shown = picked[:top]
    lines = [f"# X 每日摘要素材 · {date}", "",
             f"共 {total} 条通过筛选，以下为前 {len(shown)} 条的原始素材。"
             f"请按 prompt 规则加工成中文日报，不要照抄原文。", ""]

    for i, t in enumerate(shown, 1):
        rt = "（转发）" if t.get("is_retweet") else ""
        reply = "（回复）" if t.get("is_reply") else ""
        lines.append(f"### {i}. @{t['handle']}{rt}{reply} · {t['created_at'][:16]}")
        lines.append(t["text"])
        # 只留热度量级供判断重要性，不带符号噪音
        lines.append(f"[likes={t.get('likes', 0)} retweets={t.get('retweets', 0)}]")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def cmd_build(args) -> int:
    state = Path(args.state_dir)
    date = args.date or datetime.now().astimezone().strftime("%Y-%m-%d")
    picked_file = state / "picked" / f"{date}.json"

    if not picked_file.exists():
        # 抓取或判定没跑：明确缺哪一步，不静默输出空日报
        print(f"[error] 缺少 {picked_file}；先跑 fetch 与 jev_score", file=sys.stderr)
        return 1

    raw_picked = json.loads(picked_file.read_text())
    # picked 是新格式（含 threshold/tweets），兼容旧格式（纯数组）
    picked = raw_picked["tweets"] if isinstance(raw_picked, dict) else raw_picked
    print(build_md(picked, date, args.top))
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="导出供 LLM 加工的素材 markdown")
    b.add_argument("--state-dir", required=True)
    b.add_argument("--date", default="", help="YYYY-MM-DD，缺省今天")
    b.add_argument("--top", type=int, default=15, help="最多导出几条")
    b.set_defaults(func=cmd_build)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
