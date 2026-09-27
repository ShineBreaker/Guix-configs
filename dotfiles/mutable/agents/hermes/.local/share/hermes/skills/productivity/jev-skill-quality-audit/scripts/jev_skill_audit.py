#!/usr/bin/env python3
"""用 Jev 对 Hermes 自建 skill 做只读语义质量判定。

只读：不写任何 skill 文件，产出就是 stdout 表格 / markdown 报告。

判定口径见 SKILL.md「问题集」一节。核心是四个硬问题，其中只有
``trigger_class`` 与 ``stale_facts`` 有排序信号；``has_rules`` /
``single_session`` 是校准维度（健康 skill 上恒定贴在两端，不构成
排序依据）。

noul 返回 0~1 概率；score 返回 0~2 连续置信度，不是三档离散分，
阈值一律按连续值比较。Jev 主训练语言英文，CJK 内容绝对精度受限，
只信交叉验证后的相对排序。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

API_URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
BODY_HEAD = 6000  # 超长 SKILL.md 截断：规则与触发类在头部，尾部是可 pop 的细节
FRONTMATTER_HEAD = 8192  # description 读至少 4KB；600B 截断会漏长 description

QUESTIONS = {
    "has_rules": {
        "type": "noul",
        "instructions": (
            "Does this skill document contain imperative rules, constraints, "
            "or prohibitions an agent must follow?"
        ),
        "criteria": {
            "true": "Contains imperative rules/constraints/prohibitions stated as requirements",
            "false": "Only narration, examples, or background prose with no stated requirement",
        },
    },
    "single_session": {
        "type": "noul",
        "instructions": (
            "Is this skill's content specific to one particular session, "
            "incident, or date, with no generalizable class-level rule?"
        ),
        "criteria": {
            "true": "Tied to a specific incident/date/PR number; the lesson does not generalize",
            "false": "States a class-level rule that applies beyond the originating incident",
        },
    },
    "trigger_class": {
        "type": "noul",
        "instructions": (
            "Does the description state a decidable trigger class (the "
            "observable conditions under which this skill should be loaded), "
            "rather than merely naming a topic?"
        ),
        "criteria": {
            "true": (
                "Description states observable conditions that decide whether "
                "to load this skill"
            ),
            "false": (
                "Description only names a subject area; an agent cannot decide "
                "from it whether to load"
            ),
        },
    },
    "stale_facts": {
        "type": "noul",
        "instructions": (
            "Does this skill state version numbers, API surfaces, or tool "
            "behavior that is likely superseded by newer facts?"
        ),
        "criteria": {
            "true": "Contains version-specific or time-bound claims likely to be outdated",
            "false": "Content is structural or procedural, not tied to a specific version's behavior",
        },
    },
}

TRIGGER_FLOOR = 0.80
STALE_CEIL = 0.70


class JevError(RuntimeError):
    pass


def _api_key() -> str:
    key = os.environ.get("TYPESAFE_API_KEY", "")
    if not key:
        home = os.environ.get("HERMES_HOME", str(Path.home() / ".local/share/hermes"))
        env_file = os.path.join(home, ".env")
        hint = f"（可从 {env_file} 的 TYPESAFE_API_KEY 取）" if os.path.exists(env_file) else ""
        raise JevError(f"缺少 TYPESAFE_API_KEY 环境变量{hint}")
    return key


def _post(payload: dict, retries: int = 3) -> dict:
    """一次 Jev 请求。429/5xx 指数退避；其余错误直接抛（settings 值域错误
    会被 validator 一律回成 invalid_request，不像通路问题，重试无意义）。
    """
    import time
    import urllib.error
    import urllib.request

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


def parse_skill(path: Path) -> dict:
    """提取 name / description / 正文头部。description 用 FRONTMATTER_HEAD
    而非 600B：长 description（见过 4KB 的）被截断后会静默丢内容，
    而它正是 trigger_class 的判定对象。
    """
    text = path.read_text(errors="ignore")
    head = text[:FRONTMATTER_HEAD]
    desc = ""
    if head.startswith("---"):
        end = head.find("\n---", 3)
        fm = head[3:end if end > 0 else len(head)]
        m = re.search(r"^description\s*:\s*(.*?)(?=\n[a-zA-Z_][\w-]*\s*:|\Z)", fm, re.M | re.S)
        if m:
            desc = m.group(1).strip().strip('"').strip("'")
    return {
        "name": path.parent.name,
        "path": path,
        "category": path.parent.parent.name,
        "description": desc,
        "body_head": text[:BODY_HEAD],
        "total_chars": len(text),
        "truncated": len(text) > BODY_HEAD,
    }


def judge(skill: dict) -> dict:
    state = (
        f"Skill name: {skill['name']}\n"
        f"Description: {skill['description']}\n"
        f"--- SKILL.md body (first {BODY_HEAD} of {skill['total_chars']} chars"
        f"{'; TRUNCATED' if skill['truncated'] else ''}) ---\n"
        f"{skill['body_head']}"
    )
    d = _post({"state": state, "model": MODEL, "questions": QUESTIONS})
    a = d["answers"]
    out = {k: a[k]["noul"] for k in QUESTIONS}
    out["tokens"] = d.get("usage", {}).get("input_tokens")
    return out


def discover(root: Path, names, use_all: bool, usage_path: Path):
    if names:
        found = []
        for n in names:
            hits = sorted(root.rglob(f"*/{n}/SKILL.md")) or sorted(root.rglob(f"{n}/SKILL.md"))
            if hits:
                found.append(hits[0])
            else:
                print(f"[skip] {n}: 磁盘上找不到", file=sys.stderr)
        return found

    candidates = [p for p in root.rglob("SKILL.md") if ".archive" not in p.parts]
    if use_all:
        return sorted(candidates)

    usage: dict = {}
    try:
        usage = json.loads(usage_path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"[warn] 读不到 {usage_path} ({e})，退回 --all 行为", file=sys.stderr)
        return sorted(candidates)

    managed = {n for n, rec in usage.items()
               if isinstance(rec, dict) and rec.get("created_by") and rec.get("state") != "archived"}
    return sorted(p for p in candidates if p.parent.name in managed)


def load_meta(root: Path) -> dict:
    """cron 引用与 pinned 标记，只用于在报告里标注，不参与判定。"""
    meta: dict = {}
    try:
        for n, rec in json.loads((root / ".usage.json").read_text()).items():
            if isinstance(rec, dict):
                meta[n] = {"pinned": bool(rec.get("pinned")),
                           "state": rec.get("state"),
                           "patch_count": int(rec.get("patch_count") or 0)}
    except (OSError, json.JSONDecodeError):
        pass
    try:
        import cron.jobs  # type: ignore
        referenced = cron.jobs.referenced_skill_names()
    except Exception:
        referenced = set()
    for n in referenced:
        meta.setdefault(n, {})["cron"] = True
    return meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=os.environ.get("HERMES_HOME", str(Path.home() / ".local/share/hermes")) + "/skills")
    ap.add_argument("--names", nargs="*", help="只审这几个 skill 名")
    ap.add_argument("--all", action="store_true", help="审磁盘上全部 SKILL.md（含 unmanaged/bundled）")
    ap.add_argument("--out", help="markdown 报告输出路径")
    args = ap.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        print(f"[error] skills 根目录不存在: {root}", file=sys.stderr)
        return 1

    paths = discover(root, args.names or None, args.all, root / ".usage.json")
    if not paths:
        print("没有可审的 skill", file=sys.stderr)
        return 1

    try:
        _api_key()
    except JevError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1

    meta = load_meta(root)
    rows = []
    total_tokens = 0
    for p in paths:
        sk = parse_skill(p)
        try:
            r = judge(sk)
        except JevError as e:
            print(f"[error] {sk['name']}: {e}", file=sys.stderr)
            continue
        total_tokens += r["tokens"] or 0
        m = meta.get(sk["name"], {})
        flags = []
        if m.get("pinned"):
            flags.append("pinned")
        if m.get("cron"):
            flags.append("cron")
        if sk["truncated"]:
            flags.append(f"trunc@{BODY_HEAD}")
        rows.append({
            "name": sk["name"], "category": sk["category"],
            "trigger": r["trigger_class"], "stale": r["stale_facts"],
            "rules": r["has_rules"], "onesession": r["single_session"],
            "chars": sk["total_chars"], "desc_chars": len(sk["description"]),
            "flags": flags, "tokens": r["tokens"],
            "patch_count": m.get("patch_count"),
        })
        print(f"{sk['name']:34s} trigger={r['trigger_class']:.2f} stale={r['stale_facts']:.2f} "
              f"rules={r['has_rules']:.2f} 1sess={r['single_session']:.2f} "
              f"({sk['total_chars']}ch, desc {len(sk['description'])}ch"
              f"{', ' + '/'.join(flags) if flags else ''})")

    if not rows:
        print("没有成功判定的 skill", file=sys.stderr)
        return 1

    rows.sort(key=lambda r: (r["trigger"], -r["stale"]))
    rewrite = [r for r in rows if r["trigger"] < TRIGGER_FLOOR]
    staleish = [r for r in rows if r["stale"] > STALE_CEIL]
    both = [r for r in rows if r["trigger"] < TRIGGER_FLOOR and r["stale"] > STALE_CEIL]

    print(f"\n=== {len(rows)} skills, {total_tokens} input tokens ===")
    print(f"description 待重写 (trigger < {TRIGGER_FLOOR}): {len(rewrite)}")
    for r in rewrite:
        print(f"  {r['name']:34s} trigger={r['trigger']:.2f} desc={r['desc_chars']}ch")
    print(f"版本绑定风险 (stale > {STALE_CEIL}): {len(staleish)}")
    for r in staleish:
        print(f"  {r['name']:34s} stale={r['stale']:.2f} patches={r.get('patch_count')}")
    print(f"两者同时命中（优先处理）: {len(both)}")
    for r in both:
        print(f"  {r['name']}")
    print("\n注：只读报告，未修改任何 skill。has_rules/single_session 是校准维度，不构成排序依据。")

    if args.out:
        lines = [
            "# Jev skill 质量审核（只读）", "",
            f"- 范围: {root}",
            f"- 判定: {len(rows)} skills, {total_tokens} input tokens",
            "- 口径: noul 0~1 概率；Jev 主训练语言英文，CJK 绝对精度受限，只信交叉验证后的相对排序",
            "", "## description 待重写", "",
            "| skill | trigger_class | desc chars | flags |", "| --- | --- | --- | --- |",
        ]
        lines += [f"| {r['name']} | {r['trigger']:.2f} | {r['desc_chars']} | {'/'.join(r['flags'])} |"
                  for r in rewrite]
        lines += ["", "## 版本绑定风险", "", "| skill | stale_facts | flags |", "| --- | --- | --- |"]
        lines += [f"| {r['name']} | {r['stale']:.2f} | {'/'.join(r['flags'])} |" for r in staleish]
        Path(args.out).write_text("\n".join(lines) + "\n")
        print(f"报告已写入 {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
