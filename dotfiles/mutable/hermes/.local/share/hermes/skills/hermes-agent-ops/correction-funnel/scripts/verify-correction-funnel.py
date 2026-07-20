#!/usr/bin/env python3
"""correction-funnel skill 的 ad-hoc verify 脚本。

ad-hoc verification — not a test suite.
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

SKILL_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/correction-funnel"))

passed = 0
failed = 0


def check(name: str, ok: bool, detail: str = ""):
    global passed, failed
    status = "PASS" if ok else "FAIL"
    if ok:
        passed += 1
    else:
        failed += 1
    suffix = f" — {detail}" if detail else ""
    print(f"  [{status}] check {name}{suffix}")


# ── 1. 必备结构 ────────────────────────────────────────────────────

p = SKILL_ROOT / "SKILL.md"
check("1.skill_md_exists", p.is_file())

text = p.read_text() if p.is_file() else ""
check("2.skill_md_under_500_lines",
      len(text.splitlines()) <= 500 if text else False,
      f"{len(text.splitlines())} lines" if text else "")

check("3.frontmatter_present", text.startswith("---") if text else False)

# ── 2. 5 步流程必须都有 ───────────────────────────────────────────

for step in ["Step 1", "Step 2", "Step 3", "Step 4", "Step 5"]:
    if step not in text:
        check(f"4.{step}_present", False, "missing step")
        break
else:
    check("4.all_5_steps_present", True)

# ── 3. 三种 entry 类型必须提到 ─────────────────────────────────────

for entry in ["note", "mistake", "ascended"]:
    check(f"5.entry_{entry}_mentioned", entry in text.lower())

# ── 4. 防 over-broad lesson 必须强调 ──────────────────────────────

check("6.over_broad_lesson_guard",
      "over-broad" in text.lower() or "over broad" in text.lower(),
      "must guard against over-broad lessons")

# ── 5. memory tool 接口（个人偏好分流） ──────────────────────────

check("7.memory_tool_interface", "memory" in text and "target=" in text,
      "must reference memory tool")

# ── 6. agenote_dream 只读契约（不自动写 KB） ─────────────────────

check("8.dream_readonly_constraint",
      "只读" in text or "read-only" in text.lower() or "never" in text.lower(),
      "must emphasize dream is read-only")

# ── 7. 三类判定（durable / local-only / duplicated） ──────────────

for cls in ["durable", "local-only", "duplicated"]:
    check(f"9.classification_{cls.replace('-', '_')}", cls in text)

# ── 8. 与上下游 skill 接口 ───────────────────────────────────────

check("10.interfaces_with_task_contract", "task-contract" in text)
check("11.interfaces_with_adversarial_review", "adversarial-review-trigger" in text)
check("12.interfaces_with_agenote_base", "agenote-base" in text)

# ── 9. reference 文件存在 ──────────────────────────────────────────

ref_patterns = SKILL_ROOT / "references" / "agenote-write-patterns.md"
check("13.reference_agenote_patterns", ref_patterns.is_file())

# ── 10. 自包含性 ──────────────────────────────────────────────────

check("14.no_external_path_dependencies",
      "~/.config/agents/skills/" not in text and "~/.hermes/skills/" not in text)

# ── 11. description trigger signals ────────────────────────────────

m = re.search(r"description:\s*[\"']?(.*?)(?:[\"']?\s*$|\n)", text, re.DOTALL)
if m:
    desc = m.group(1).strip()
    first_sentence = re.split(r"[。\n]", desc)[0]
    signals = ["correction", "funnel", "沉淀", "KB"]
    found = [w for w in signals if w.lower() in first_sentence.lower()]
    check("15.description_trigger_signals", len(found) >= 1,
          f"signals: {found}")
else:
    check("15.description_present", False, "no description")

print(f"\n{passed}/{passed + failed} PASS")
print("\nad-hoc verification — not a test suite")
sys.exit(0 if failed == 0 else 1)