#!/usr/bin/env python3
"""agenote 卡片全量 Jev 质量判定（只读，产出待处置清单）。

判定口径（corpus-quality-audit / jev-skill-quality-audit 同源）：
- no_value  : 无任何可迁移教训（纯流水账 / 空模板节 / 一次性细节）
- duplicated: 核心教训已被同库其他卡片完全覆盖，无新增信息
- stale_risk: 版本号 / API 行为绑定，可能已被新事实取代
noul 返回 0~1 概率；Jev 主训练语言英文，CJK 绝对精度受限，
只信交叉验证后的相对排序。以 no_value >= 0.75 为「无用候选」，
duplicated >= 0.70 为「重复候选」，两者都只进清单、不自动删。
"""
from __future__ import annotations
import argparse, json, os, pathlib, sys, time, urllib.request

API_URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
HEAD = 6000  # 超长卡片截断：规则与结论在前，尾部是可 pop 的细节

QUESTIONS = {
    "no_value": {
        "type": "noul",
        "instructions": (
            "Does this card record no reusable lesson: no symptom/root-cause pair, "
            "no procedure, no configuration fact usable in a future task?"
        ),
        "criteria": {
            "true": "Flat progress log, empty template sections, or single-shot detail with no transferable lesson",
            "false": "Contains a symptom, a cause, a procedure, or a concrete fact usable later",
        },
    },
    "duplicated": {
        "type": "noul",
        "instructions": (
            "Is this card's core lesson already fully covered by another card in the "
            "same knowledge base (same symptom, same root cause, same fix, no new information)?"
        ),
        "criteria": {
            "true": "Another card covers the same lesson; this adds no new information",
            "false": "The lesson is distinct from all other cards",
        },
    },
    "stale_risk": {
        "type": "noul",
        "instructions": (
            "Does this card state version numbers, API surfaces, or tool behavior "
            "likely superseded by newer facts?"
        ),
        "criteria": {
            "true": "Contains version-specific or time-bound claims likely outdated",
            "false": "Content is structural or procedural, not tied to a version's behavior",
        },
    },
}

NOVALUE_FLOOR = 0.75
DUP_FLOOR = 0.70
STALE_CEIL = 0.70


def _api_key() -> str:
    key = os.environ.get("TYPESAFE_API_KEY", "")
    if not key:
        raise RuntimeError(
            "缺少 TYPESAFE_API_KEY（运行前执行: "
            'export TYPESAFE_API_KEY="$(secrets get typesafe TYPESAFE_API_KEY)"）'
        )
    return key


def _post(payload: dict, retries: int = 4) -> dict:
    import urllib.error
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
                time.sleep(5 * (2 ** attempt)); continue
            raise RuntimeError(f"HTTP {e.code}: {detail!r}") from e
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            if attempt < retries - 1:
                time.sleep(5 * (2 ** attempt)); continue
            raise RuntimeError(f"network: {e}") from e
    raise RuntimeError("unreachable")


def judge(title: str, text: str) -> tuple[dict, int | None]:
    state = (f"Knowledge-base card title: {title}\n"
             f"--- org card body (first {HEAD} of {len(text)} chars"
             f"{'; TRUNCATED' if len(text) > HEAD else ''}) ---\n{text[:HEAD]}")
    d = _post({"state": state, "model": MODEL, "questions": QUESTIONS})
    a = d["answers"]
    return {k: a[k]["noul"] for k in QUESTIONS}, d.get("usage", {}).get("input_tokens")


def parse_body(path: pathlib.Path) -> str:
    """去掉属性抽屉与标签行，保留正文（去掉比保留更省 token）。"""
    text = path.read_text(errors="ignore")
    lines = []
    drawer = False
    for ln in text.splitlines():
        s = ln.strip()
        if s == ":PROPERTIES:":
            drawer = True; continue
        if drawer:
            if s == ":END:": drawer = False
            continue
        if s.startswith(":") and s.endswith(":"):  # 标签行
            continue
        if s.startswith("*"):  # 标题行（第一条已由 title 给出）
            continue
        lines.append(ln)
    return "\n".join(lines).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(pathlib.Path.home() / "Documents/Org/agenote"))
    ap.add_argument("--out", default="jev-cards.jsonl")
    ap.add_argument("--limit", type=int, default=0, help="只跑前 N 张（探针用）")
    ap.add_argument("--resume", action="store_true", help="跳过 out 里已有的 id")
    ap.add_argument("--include-archived", action="store_true")
    args = ap.parse_args()

    root = pathlib.Path(args.root)
    index = json.load(open(root / "index.json"))
    done_ids: set[str] = set()
    if args.resume and pathlib.Path(args.out).exists():
        for ln in open(args.out):
            try: done_ids.add(json.loads(ln)["id"])
            except Exception: pass
        print(f"[resume] 已完成 {len(done_ids)} 张", file=sys.stderr)

    cards = [c for c in index["cards"]
             if args.include_archived or c["status"] != "archived"]
    if args.limit:
        cards = cards[:args.limit]

    fout = open(args.out, "a")
    total_tokens = 0; errors = 0
    for i, c in enumerate(cards, 1):
        if c["id"] in done_ids: continue
        p = root / c["file"]
        if not p.exists():
            print(f"[warn] missing {c['file']}", file=sys.stderr); continue
        body = parse_body(p)
        try:
            sc, tok = judge(c["title"], body)
        except Exception as e:
            errors += 1
            print(f"[error] {c['id']} {c['title'][:30]}: {e}", file=sys.stderr); continue
        total_tokens += tok or 0
        rec = {"id": c["id"], "title": c["title"], "category": c["category"],
               "type": c["type"], "tech": c["tech"], "status": c["status"],
               "usage_count": c.get("usage_count") or 0, "file": c["file"], **sc}
        fout.write(json.dumps(rec, ensure_ascii=False) + "\n"); fout.flush()
        if i % 25 == 0:
            print(f"[{i}/{len(cards)}] tokens={total_tokens} errors={errors}", file=sys.stderr)
    fout.close()
    print(f"完成：{len(cards)} 张，{total_tokens} input tokens，{errors} 个错误")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
