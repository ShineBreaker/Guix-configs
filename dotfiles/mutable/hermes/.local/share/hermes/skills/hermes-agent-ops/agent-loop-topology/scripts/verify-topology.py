#!/usr/bin/env python3
"""agent-loop-topology reference 文档的轻量 verify。

ad-hoc verification — not a test suite.

注：这是 reference 文档（不是 skill），验证轻量：基本结构 + Mermaid 语法 OK + 内容覆盖。
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path

DOC_ROOT = Path(os.path.expanduser(
    "~/.local/share/hermes/skills/hermes-agent-ops/agent-loop-topology"))

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

p = DOC_ROOT / "README.md"
check("1.readme_exists", p.is_file())

text = p.read_text() if p.is_file() else ""

# ── 2. Mermaid 块 ──────────────────────────────────────────────────

mermaid_match = re.search(r"```mermaid\n(.*?)\n```", text, re.DOTALL)
check("2.mermaid_block_present", mermaid_match is not None,
      f"found at offset {mermaid_match.start()}" if mermaid_match else "")

if mermaid_match:
    m_text = mermaid_match.group(1)
    # Mermaid 语法基本检查
    has_graph = "graph TB" in m_text or "graph TD" in m_text
    has_subgraphs = "subgraph" in m_text
    has_classes = "classDef" in m_text
    check("3.mermaid_has_graph_declaration", has_graph)
    check("4.mermaid_has_subgraphs", has_subgraphs)
    check("5.mermaid_has_classdef", has_classes)

# ── 3. 四类循环必须覆盖 ───────────────────────────────────────────

for loop_type in ["慢循环", "中循环", "快循环", "监控循环", "锚"]:
    check(f"6.{loop_type}_section_present", loop_type in text)

# ── 4. Goodhart 四失败映射 ───────────────────────────────────────

goodhart_failures = ["metric 被攻破", "盲向上", "循环间冲突", "测量退化"]
all_present = all(g in text for g in goodhart_failures)
check("7.goodhart_four_failures_mapped", all_present)

# ── 5. frozen rule + anchor + audit 概念覆盖 ──────────────────────

for concept in ["frozen", "anchor", "audit", "Goodhart", "Perez", "punkjazz"]:
    check(f"8.{concept}_mentioned", concept in text)

# ── 6. 至少 4 个 hermes 实际 skill 在图里 ─────────────────────────

skills_in_topology = ["task-contract", "adversarial-review-trigger",
                      "worker-handoff", "authority-gate", "correction-funnel"]
mentioned = [s for s in skills_in_topology if s in text]
check("9.skills_in_topology", len(mentioned) >= 4,
      f"mentioned: {mentioned}")

# ── 7. self-contained (no external path deps) ─────────────────────

check("10.no_external_path_dependencies",
      "~/.config/agents/skills/" not in text and "~/.hermes/skills/" not in text)

print(f"\n{passed}/{passed + failed} PASS")
print("\nad-hoc verification — not a test suite")
sys.exit(0 if failed == 0 else 1)