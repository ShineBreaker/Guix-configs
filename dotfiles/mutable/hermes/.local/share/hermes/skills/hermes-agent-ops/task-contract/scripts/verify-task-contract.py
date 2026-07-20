#!/usr/bin/env python3
"""task-contract skill 的 ad-hoc verify 脚本。

按 skill-authoring §8 要求，每个 skill 在同一 turn 必须出 PASS/FAIL tally。
这是「图论→技能化」任务的契约中 F1 / F4 的 verify。

ad-hoc verification — not a test suite.
"""
from __future__ import annotations
import os
import re
import sys
import tempfile
from pathlib import Path

SKILL_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/task-contract"))

CHECKS: list[tuple[str, str, callable]] = []  # (num, key, fn)


def check(name: str, key: str):
    def deco(fn):
        CHECKS.append((name, key, fn))
        return fn
    return deco


# ── 1. 必备文件结构 ────────────────────────────────────────────────

@check("1", "skill_md_exists")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    if not p.is_file():
        return ("FAIL", f"missing {p}")
    text = p.read_text()
    if not text.startswith("---"):
        return ("FAIL", "SKILL.md does not start with YAML frontmatter")
    return ("PASS", f"{len(text)} bytes")


@check("2", "skill_md_under_500_lines")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    lines = p.read_text().splitlines()
    if len(lines) > 500:
        return ("FAIL", f"SKILL.md has {len(lines)} lines, exceeds 500 hard ceiling")
    return ("PASS", f"{len(lines)} lines")


@check("3", "frontmatter_required_fields")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return ("FAIL", "no frontmatter found")
    fm = m.group(1)
    required = ["name:", "description:", "version:", "metadata:"]
    missing = [r for r in required if r not in fm]
    if missing:
        return ("FAIL", f"missing frontmatter fields: {missing}")
    return ("PASS", "all required fields present")


@check("4", "name_in_frontmatter_matches_dir")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    m = re.search(r"^name:\s*(\S+)", text, re.MULTILINE)
    if not m:
        return ("FAIL", "no name: in frontmatter")
    name = m.group(1).strip()
    expected = SKILL_ROOT.name
    if name != expected:
        return ("FAIL", f"frontmatter name='{name}' != dir name='{expected}'")
    return ("PASS", f"name='{name}' matches dir")


@check("5", "template_present")
def _(t):
    p = SKILL_ROOT / "templates" / "contract.md"
    if not p.is_file():
        return ("FAIL", f"missing {p}")
    text = p.read_text()
    required_sections = ["False-Success", "Expected Evidence", "Verification Approach", "Replan Budget"]
    missing = [s for s in required_sections if s not in text]
    if missing:
        return ("FAIL", f"template missing sections: {missing}")
    return ("PASS", f"{len(text)} bytes, all 4 sections present")


@check("6", "reference_example_present")
def _(t):
    p = SKILL_ROOT / "references" / "example-graph-engineering-translation.md"
    if not p.is_file():
        return ("FAIL", f"missing {p}")
    text = p.read_text()
    if "False-Success" not in text or "graph" not in text.lower():
        return ("FAIL", "reference missing expected content")
    return ("PASS", f"{len(text)} bytes")


# ── 2. 触发词质量（描述里必须含可触发信号词） ───────────────────────────

@check("7", "description_has_trigger_signals")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    m = re.search(r"description:\s*[\"']?(.*?)(?:[\"']?\s*$|\n)", text, re.DOTALL)
    if not m:
        return ("FAIL", "no description")
    desc = m.group(1).strip()
    # 用户硬偏好：trigger 词要在前两句
    first_sentence = re.split(r"[。\n]", desc)[0]
    signal_words = ["触发", "task contract", "false-success", "开始", "触发词"]
    found = [w for w in signal_words if w in first_sentence]
    if not found:
        return ("FAIL", f"first sentence lacks trigger signals: '{first_sentence}'")
    return ("PASS", f"signals: {found}")


# ── 3. 端到端模拟：用模板生成一份契约，验证可填空 ─────────────────────────

@check("8", "template_fillable_end_to_end")
def _(t):
    """模拟 agent 加载模板后能正确填入 false-success / evidence / verification / replan 四段。"""
    template = (SKILL_ROOT / "templates" / "contract.md").read_text()
    fillers = {
        "F1": "任务说做完了，但磁盘上没有 working artifact",
        "F2": "测试套件绿，但 success criteria 被偷偷改了",
        "F3": "git status 干净，但 commit log 看不到做过的痕迹",
        "<任务简述>": "verify-fixture-task",
        "___": "1",
    }
    filled = template
    for k, v in fillers.items():
        filled = filled.replace(k, v)
    # 检查 4 段都还有（不是被误删）
    missing = []
    for sec in ["False-Success", "Expected Evidence", "Verification Approach", "Replan Budget"]:
        if sec not in filled:
            missing.append(sec)
    if missing:
        return ("FAIL", f"after fill, sections missing: {missing}")
    return ("PASS", "template fillable, 4 sections preserved")


@check("11", "paired_metrics_in_template")
def _(t):
    """Perez Paired Metrics: template 必须有 counter-metric 段。"""
    p = SKILL_ROOT / "templates" / "contract.md"
    text = p.read_text()
    if "Counter-Metric" not in text:
        return ("FAIL", "template missing Counter-Metric section")
    if "counter" not in text.lower() or "success" not in text.lower():
        return ("FAIL", "template must mention counter/success pairing")
    if "Goodhart" not in text:
        return ("FAIL", "template must reference Goodhart's law context")
    return ("PASS", "paired metrics present with Goodhart context")


@check("12", "no_external_path_dependencies")
def _(t):
    """SKILL.md 不应引用 ~/.config/agents/skills/ 或 ~/.hermes/skills/ 等外部 skill 源路径。"""
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    forbidden = ["~/.config/agents/skills/", "~/.hermes/skills/"]
    hits = [f for f in forbidden if f in text]
    if hits:
        return ("FAIL", f"external path references found: {hits}")
    return ("PASS", "no external path references")


# ── 5. cross-link 健康度 ────────────────────────────────────────────

@check("13", "related_skills_field_present")
def _(t):
    p = SKILL_ROOT / "SKILL.md"
    text = p.read_text()
    if "related_skills:" not in text:
        return ("FAIL", "no related_skills field")
    return ("PASS", "related_skills present")


# ── main ───────────────────────────────────────────────────────────

def main():
    print(f"task-contract ad-hoc verify @ {SKILL_ROOT}\n")
    passed = 0
    failed = 0
    for num, key, fn in CHECKS:
        status, detail = fn(None)
        if status == "PASS":
            passed += 1
        else:
            failed += 1
        print(f"  [{status}] check {num}: {key} — {detail}")
    print(f"\n{passed}/{passed + failed} PASS")
    print("\nad-hoc verification — not a test suite")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())