#!/usr/bin/env python3
"""adversarial-review-trigger skill 的 ad-hoc verify 脚本。

ad-hoc verification — not a test suite.
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

SKILL_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/adversarial-review-trigger"))


def check(num: str, key: str, fn):
    print(f"  [{fn() and 'PASS' or 'FAIL'}] check {num}: {key}")
    return bool(fn())


# ── 1. 必备结构 ────────────────────────────────────────────────────

def c1():
    p = SKILL_ROOT / "SKILL.md"
    if not p.is_file():
        print(f"    missing {p}")
        return False
    text = p.read_text()
    if not text.startswith("---"):
        print("    SKILL.md missing YAML frontmatter")
        return False
    return True


def c2():
    p = SKILL_ROOT / "SKILL.md"
    lines = p.read_text().splitlines()
    if len(lines) > 500:
        print(f"    SKILL.md {len(lines)} lines > 500 ceiling")
        return False
    return True


# ── 2. 必须含 attack vector 清单（≥10 个） ──────────────────────────

def c3():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    # 检查所有 A1-A10 是否都出现
    missing = []
    for i in range(1, 11):
        if f"A{i}:" not in text and f"A{i} " not in text:
            missing.append(f"A{i}")
    if missing:
        print(f"    missing attack vectors: {missing}")
        return False
    return True


# ── 3. 必须强调 framing 改变（不是验证 happy path） ────────────────────

def c4():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    required_phrases = ["试图推翻", "对抗", "attacker", "adversarial", "happy path"]
    found = [p for p in required_phrases if p in text.lower()]
    if len(found) < 2:
        print(f"    insufficient framing-shift signals: found {found}")
        return False
    return True


# ── 4. 独立性硬约束（防同 blind spot） ──────────────────────────────

def c5():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    # 必须提到 model 独立性 / different framing
    if "delegate_task" not in text or "model" not in text:
        print("    missing independence guidance (delegate_task / model)")
        return False
    return True


# ── 5. 与上下游 skill 的接口 ────────────────────────────────────────

def c6():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    if "related_skills" not in text:
        print("    no related_skills field")
        return False
    required = ["task-contract", "code-reviewer", "correction-funnel"]
    for r in required:
        if r not in text:
            print(f"    missing related skill: {r}")
            return False
    return True


# ── 6. reference 引用 punkjazz 原文（佐证方法论来源） ────────────────

def c7():
    p = SKILL_ROOT / "references" / "punkjazz-graph-engineering-quotes.md"
    if not p.is_file():
        print(f"    missing {p}")
        return False
    text = p.read_text()
    required_quotes = [
        "give the result to a fresh reviewer whose job is to disprove",
        "theater dressed as verification",
    ]
    missing = [q for q in required_quotes if q not in text]
    if missing:
        print(f"    missing quotes: {missing}")
        return False
    return True


# ── 7. 自包含性 ────────────────────────────────────────────────────

def c8():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    forbidden = ["~/.config/agents/skills/", "~/.hermes/skills/"]
    hits = [f for f in forbidden if f in text]
    if hits:
        print(f"    external path references: {hits}")
        return False
    return True


# ── 8. description trigger signals ──────────────────────────────────

def c9():
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    m = re.search(r"description:\s*[\"']?(.*?)(?:[\"']?\s*$|\n)", text, re.DOTALL)
    if not m:
        print("    no description")
        return False
    desc = m.group(1).strip()
    first_sentence = re.split(r"[。\n]", desc)[0]
    signals = ["adversarial", "完工", "对抗", "推翻"]
    found = [w for w in signals if w.lower() in first_sentence.lower()]
    if not found:
        print(f"    first sentence lacks trigger signals: '{first_sentence}'")
        return False
    return True


passed = 0
failed = 0
for num, key, fn in [
    ("1", "skill_md_exists_with_frontmatter", c1),
    ("2", "skill_md_under_500_lines", c2),
    ("3", "all_10_attack_vectors_present", c3),
    ("4", "framing_shift_signals", c4),
    ("5", "independence_hard_constraints", c5),
    ("6", "skill_interface_to_upstream_downstream", c6),
    ("7", "reference_quotes_present", c7),
    ("8", "no_external_path_dependencies", c8),
    ("9", "description_trigger_signals", c9),
]:
    if fn():
        passed += 1
        print(f"  [PASS] check {num}: {key}")
    else:
        failed += 1
        print(f"  [FAIL] check {num}: {key}")

print(f"\n{passed}/{passed + failed} PASS")
print("\nad-hoc verification — not a test suite")
sys.exit(0 if failed == 0 else 1)