#!/usr/bin/env python3
"""用 jev 判定推文是否值得进日报。

jev 是 TypeSafe 的 System One 模型（POST /v1/systemone，API key 走
TYPESAFE_API_KEY 环境变量）。它不做文本生成，只对结构化问题返回校准过的
概率/分值 —— 正适合"这条值不值得读"这种二分类 + 打分场景。

用法:
    jev_score.py score --input <new>.json [--state-dir DIR] [--threshold 0.6]
                       [--batch-size 8]

产出:
    <state>/scored/YYYY-MM-DD.json   全部推文 + 分数 + 入选标记
    <state>/picked/YYYY-MM-DD.json   仅入选推文，按综合分降序 —— 日报的输入

判定口径（三条问题，一次请求批量返回）:
    worth_reading  noul   有没有值得读的实质内容
    novelty        score  新信息量（0 常识 / 1 有点用 / 2 具体且反直觉）
    signal         score  信息密度与可执行性（0 无价值 / 1 一个可用点 / 2 密集可执行）
入选规则（2026-09-22 实测校准）:
    signal >= 1.0             主判据（jev 输出 0~2 分制，非 0~1）
    worth_reading >= 0.3     辅助门槛，只用来挡纯链接/口水
排序:   signal * 0.6 + novelty * 0.4 加权综合分（可执行性优先）
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

API_URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
THRESHOLD_DEFAULT = 1.0     # signal 入选阈值（jev 输出 0~2 分制）
WORTH_FLOOR = 0.3           # worth_reading 辅助门槛
BATCH_SIZE_DEFAULT = 8

QUESTIONS = {
    "worth_reading": {
        "type": "noul",
        "instructions": ("Does this tweet contain substantive information, an original "
                         "insight, or an actionable idea worth reading in a daily digest?"),
        "criteria": {
            "true": ("Concrete information, original insight, or an actionable idea "
                     "readable without opening any link"),
            "false": "Pure link drop, greeting, banter, empty engagement, or hot take "
                     "with no substance behind it",
        },
    },
    "novelty": {
        "type": "score",
        "instructions": "How much new information does this tweet provide?",
        "criteria": ["Common knowledge or platitude",
                     "Somewhat useful new framing",
                     "Specific and non-obvious insight"],
    },
    "signal": {
        "type": "score",
        "instructions": "Rate the information density and actionability of this tweet.",
        "criteria": ["No information value",
                     "Moderate: one usable point",
                     "High: dense with concrete, actionable substance"],
    },
}


class JevError(RuntimeError):
    pass


def _post(payload: dict, retries: int = 3) -> dict:
    body = json.dumps(payload).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                API_URL, data=body,
                headers={"Authorization": f"Bearer {_api_key()}",
                         "Content-Type": "application/json"},
                method="POST")
            with urllib.request.urlopen(req, timeout=90) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            detail = e.read()[:300]
            if e.code in (429, 500, 503, 529) and attempt < retries - 1:
                time.sleep(5 * (2 ** attempt))
                continue
            raise JevError(f"HTTP {e.code}: {detail!r}") from e
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            if attempt < retries - 1:
                time.sleep(5 * (2 ** attempt))
                continue
            raise JevError(f"network: {e}") from e
    raise JevError("unreachable after retries")


def _api_key() -> str:
    key = os.environ.get("TYPESAFE_API_KEY", "")
    if not key:
        raise JevError("缺少 TYPESAFE_API_KEY 环境变量（.env 中配置）")
    return key


def score_batch(tweets: list[dict]) -> list[dict]:
    """逐条判定。

    jev 的 state 即使是数组也只当整体语境处理、answers 不逐元素展开
    （2026-09-22 实测：两条 state 只回一个 noul），故一条一次请求。
    批内仅共享 0.4s 限速，见 cmd_score 循环。
    """
    out: list[dict] = []
    for t in tweets:
        state = f"Author: @{t['handle']}\nText: {t['text']}\nLikes: {t['likes']}"
        try:
            d = _post({"state": state, "model": MODEL, "questions": QUESTIONS})
        except JevError as e:
            print(f"[warn] jev 判定失败 ({t.get('id')}): {e}", file=sys.stderr)
            out.append({"worth": None, "novelty": None, "signal": None, "error": str(e)})
            continue
        a = d["answers"]
        out.append({
            "worth": a["worth_reading"]["noul"],
            "novelty": a["novelty"]["score"],
            "signal": a["signal"]["score"],
            "tokens": d.get("usage", {}).get("input_tokens"),
        })
    return out


def cmd_score(args) -> int:
    key = _api_key()  # 早失败：密钥缺失就不要白跑抓取
    src = Path(args.input)
    if not src.exists():
        print(f"[error] 输入不存在: {src}", file=sys.stderr)
        return 1
    tweets = json.loads(src.read_text())
    if not tweets:
        print("输入为空，无需判定")
        return 0

    state = Path(args.state_dir)
    for sub in ("scored", "picked"):
        (state / sub).mkdir(parents=True, exist_ok=True)

    results: list[dict] = []
    for i in range(0, len(tweets), args.batch_size):
        batch = tweets[i:i + args.batch_size]
        scores = score_batch(batch)
        for t, s in zip(batch, scores):
            row = dict(t)
            row["scores"] = s
            w, sig = s.get("worth"), s.get("signal")
            row["picked"] = (w is not None and sig is not None
                             and sig >= args.threshold and w >= WORTH_FLOOR)
            row["composite"] = (round(s["signal"] * 0.6 + s["novelty"] * 0.4, 3)
                                if (s.get("signal") is not None
                                    and s.get("novelty") is not None) else None)
            results.append(row)
        time.sleep(0.4)  # 温和限速，远低于 1200 req/min

    picked = sorted((r for r in results if r["picked"]),
                    key=lambda r: r["composite"] or 0, reverse=True)
    today = datetime.now().astimezone().strftime("%Y-%m-%d")
    (state / "scored" / f"{today}.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2))
    # 落盘生效阈值：旧进程带旧阈值跑完时，读方一眼能看出这份 picked
    # 是哪个口径产出的，不会把阈值变更误读成筛选结果变化。
    (state / "picked" / f"{today}.json").write_text(json.dumps({
        "threshold": args.threshold,
        "worth_floor": WORTH_FLOOR,
        "tweets": picked,
    }, ensure_ascii=False, indent=2))

    failed = sum(1 for r in results if r["scores"].get("worth") is None)
    print(f"scored={len(results)} picked={len(picked)} failed={failed} "
          f"threshold={args.threshold}")
    # 判定失败不阻塞日报：日报阶段自行呈现"本条未判定"
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("score", help="判定一批推文的价值")
    s.add_argument("--input", required=True, help="fetch 产出的 new/*.json")
    s.add_argument("--state-dir", required=True)
    s.add_argument("--threshold", type=float, default=THRESHOLD_DEFAULT,
                   help="signal 入选阈值，默认 0.6")
    s.add_argument("--batch-size", type=int, default=BATCH_SIZE_DEFAULT,
                   help="每几条之间 sleep 0.4s 的限速单位，默认 8")
    s.set_defaults(func=cmd_score)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
