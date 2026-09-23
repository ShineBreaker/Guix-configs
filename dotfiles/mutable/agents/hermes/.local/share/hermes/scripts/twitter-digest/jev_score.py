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

判定口径（五条问题，一次请求批量返回）:
    worth_reading  noul   有没有值得读的实质内容
    novelty        score  新信息量（0 常识 / 1 有点用 / 2 具体且反直觉）
    signal         score  信息密度与可执行性（0 无价值 / 1 一个可用点 / 2 密集可执行）
    has_facts      noul   有没有可检索的硬事实（版本号/参数/价格/跑分/日期）
    is_news        noul   是不是一件可陈述的新闻事件（任何领域，不限 AI）
    is_release     noul   是不是产品/模型/版本的发布官宣

入选规则（2026-09-23 重新校准，取代 2026-09-22 版）:
    is_news >= 0.5           主判据：挡掉观点/吐槽/互动/晒日常
    is_release >= 0.5        发布官宣走旁路
    is_news >= 0.85          高新闻价值同样走发布通道（榜单成绩/官方说明/实测反馈）
    非官宣条目：
        worth_reading >= 0.3     辅助门槛，挡纯链接/口水
        signal >= 1.0            保底，挡"有事实但极空洞"
    注：score 类型返回的是 0~2 连续置信度，不是 0/1/2 三档离散分
    （217 条实测仅 13 条落在整数档），所以 threshold 是连续值比较。
    has_facts 不设硬门槛：noul 对"无数字但有实质"的内容（架构说明、
    工具改版、踩坑记录）天然给低分，实测误杀 6 条，只让它参与排序。
    主题不设门槛：政策、法律、商业、科技、健康都有新闻价值，
    2026-09-23 前用 for_engineer 挡非 AI 内容是错的，已废除。
    is_release 旁路是必需的：官宣句式短促（"X is now available"），
    signal/worth 天然偏低，2026-09-23 实测 Opus 5.5 的官宣推文
    signal=0.98、worth=0.37 被双线卡掉，只剩测评进日报。
    is_news 高分区（>=0.85）同样放行：官宣的后续侧面（榜单成绩、
    官方说明、实测反馈）is_release 常判不满——实测 Opus 5.5 的
    "takes the #1 spot" rel=0.10 news=0.92 sig=0.97 被 signal 线
    卡掉，官方转发 rel=0.49 news=0.87 踩线。发布事件的各侧面
    都放进来，由 prompt 的合并规则收成一条。

排序:   composite = (signal*0.5 + novelty*0.3 + has_facts*0.4) / 2，归一到 0~1
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
THRESHOLD_DEFAULT = 1.0     # signal 保底阈值（jev 输出 0~2 连续值）
WORTH_FLOOR = 0.3           # worth_reading 辅助门槛
NEWS_FLOOR = 0.5             # is_news 门槛（noul 0~1）
RELEASE_FLOOR = 0.5          # is_release 门槛，命中即绕过 signal/worth 保底
RELEASE_NEWS_FLOOR = 0.85    # is_news 达到此值也走发布通道（官宣的后续侧面）
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
    # 硬事实判定：有具体数字、版本号、价格、跑分、日期等可检索实体。
    # 上面三条问"质量"，jev 给平滑连续值、没有决策边界；这一条问"有没有
    # 干货"，二分类边界清晰，是入选的主判据。
    "has_facts": {
        "type": "noul",
        "instructions": ("Does this tweet state concrete, verifiable facts such as "
                         "version numbers, parameter counts, benchmark scores, prices, "
                         "dates, or license changes?"),
        "criteria": {
            "true": ("Contains at least one specific number, version, model name, "
                     "price, date, or benchmark result that a reader could act on "
                     "or look up"),
            "false": ("Opinion, announcement without specifics, question, banter, "
                      "or content whose substance is only behind a link"),
        },
    },
    # 发布事实判定：产品/模型/版本正式上线的官宣。这类内容句式短促
    # （"X is now available"），信息密度天然不高，signal 和 worth 都偏低，
    # 但它是新闻本身，必须进日报。命中即绕过 signal/worth 保底线。
    # 2026-09-23 实证：Opus 5.5 三条推文里，官宣那条 signal=0.98、
    # worth=0.37 被双线卡掉，只剩体验测评进了日报——发布事实反被丢掉。
    "is_release": {
        "type": "noul",
        "instructions": ("Does this tweet announce that a product, model, version, "
                         "or feature has shipped, become available, or launched, "
                         "stating what was released?"),
        "criteria": {
            "true": ("States a release or availability fact: 'X is now available', "
                     "'X ships today', 'X launches', a version number with a "
                     "release, or an official launch announcement"),
            "false": ("Review, benchmark, hands-on, opinion about a release, or "
                      "news that is not about something becoming available"),
        },
    },
    # 新闻价值判定：与主题无关。政策、法律、商业、科技、社会事件都算，
    # 只要它是"发生了某件可陈述的事实"。这条挡掉的是观点、吐槽、
    # 互动、晒日常，不是挡非 AI 话题。
    "is_news": {
        "type": "noul",
        "instructions": ("Does this tweet report a specific event, decision, "
                         "release, or finding that happened or was announced, "
                         "in any domain such as technology, science, business, "
                         "policy, law, or health?"),
        "criteria": {
            "true": ("Reports a concrete event or announcement: a product or "
                     "model release, a legal or regulatory decision, a funding "
                     "or business deal, a research finding, a benchmark result, "
                     "an incident, or a policy change"),
            "false": ("Personal opinion, reaction, banter, self-promotion, "
                      "engagement bait, question, or commentary with no "
                      "underlying event"),
        },
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
            "has_facts": a["has_facts"]["noul"],
            "is_news": a["is_news"]["noul"],
            "is_release": a["is_release"]["noul"],
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
            news = s.get("is_news")
            rel = s.get("is_release")
            if (w is None or sig is None or news is None or rel is None):
                row["picked"] = False
            else:
                # 入选：新闻价值 + 可读性 + signal 保底。
                # has_facts 不设硬门槛：noul 对"无数字但有实质"的内容
                # （架构说明、工具改版、踩坑记录）天然给低分，2026-09-23
                # 实测误杀 6 条。它只参与 composite 排序。
                # 主题也不设门槛：不限 AI，任何领域的新闻都进日报。
                # 发布事件通道：官宣（is_release）句式短促，signal/worth
                # 天然偏低；官宣的后续（榜单成绩、官方说明、实测反馈）
                # is_release 也常判不满。is_news 足够高就放行，让发布事件
                # 的各个侧面都进来，由 prompt 的合并规则收成一条。
                if (rel >= RELEASE_FLOOR
                        or news >= RELEASE_NEWS_FLOOR):
                    row["picked"] = True
                else:
                    row["picked"] = bool(
                        news >= args.news
                        and w >= WORTH_FLOOR and sig >= args.threshold)
            # composite 归一到 0~1：signal/novelty 是 0~2 连续值，
            # 不归一化会让排序被量纲带着跑。has_facts 占 0.2 权重，
            # 让有硬事实的条目排在同等质量的前面
            row["composite"] = (round((s["signal"] * 0.5 + s["novelty"] * 0.3
                                       + (s.get("has_facts") or 0) * 0.4) / 2, 3)
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
        "news": args.news,
        "release": RELEASE_FLOOR,
        "tweets": picked,
    }, ensure_ascii=False, indent=2))

    failed = sum(1 for r in results if r["scores"].get("worth") is None)
    print(f"scored={len(results)} picked={len(picked)} failed={failed} "
          f"threshold={args.threshold} news={args.news} "
          f"release={RELEASE_FLOOR}/{RELEASE_NEWS_FLOOR}")
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
                   help="signal 保底阈值（0~2 连续值），默认 1.0")
    s.add_argument("--news", type=float, default=NEWS_FLOOR,
                   help="is_news 门槛（noul 0~1)，默认 0.5")
    s.add_argument("--release", type=float, default=RELEASE_FLOOR,
                   help="is_release 旁路门槛（noul 0~1)，默认 0.5")
    s.add_argument("--batch-size", type=int, default=BATCH_SIZE_DEFAULT,
                   help="每几条之间 sleep 0.4s 的限速单位，默认 8")
    s.set_defaults(func=cmd_score)
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
