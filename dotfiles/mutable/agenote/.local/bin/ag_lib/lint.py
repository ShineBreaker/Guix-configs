# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""agenote lint — 知识库格式与语义校验（纯检查器）。

与 format 的分工：
  - format（ag_lib.orgfmt）：执行可安全自动化的格式化（属性对齐、block 大小写、
    空行、表格、MD→Org、标记间距），默认直接写盘。
  - lint（本模块）：报告**全部**问题——格式问题（调 format_org 做 diff）+
    语义问题（枚举漂移、缺失字段、fingerprint 字段数、卡片骨架）。
    语义问题需要人工判断或破坏性改动，不自动修。

命令形态：
  - agenote lint            报告格式 + 语义问题
  - agenote lint --fix      只自动修可安全自动化的（= 调 format_org）
  - agenote lint --check    报告 + 退出码=问题数（CI/pre-commit 用）
"""

import argparse
import os
import re
import sys

from ag_lib.core import (
    VALID_TYPES,
    VALID_OWNERS,
    VALID_ENTRY_TYPES,
    die,
    default_context,
    parse_org_prop,
)
from ag_lib.orgfmt import format_org


# ═══════════════════════════════════════════════════════════════════════════════
# lint 命令 — 格式 + 语义校验
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_lint(args: argparse.Namespace, ctx=None) -> None:
    """检查卡片格式 + 语义问题，可选自动修复格式问题。

    格式问题：调 format_org(text, strict=True) 做 diff，报告所有变更。
    语义问题：枚举漂移、缺失字段、fingerprint 字段数、卡片骨架章节缺失。
    --fix 只修格式问题（= format），语义问题始终只报告。
    --check 设退出码 = 问题数（≤127）。
    """
    ctx = ctx or default_context()
    target_files = args.files
    if not target_files:
        target_files = sorted(
            f for f in ctx.experiences.rglob("*.org") if not f.is_symlink()
        )
        target_files = [str(p) for p in target_files]

    if not target_files:
        die("未找到 .org 文件")

    total_issues = 0
    files_with_issues = 0

    for filepath in target_files:
        issues = _lint_file(filepath, do_fix=args.fix)
        if issues:
            total_issues += len(issues)
            files_with_issues += 1
            basename = os.path.basename(filepath)
            print(f"\n{basename} ({len(issues)} 项):")
            for issue in issues:
                print(issue)

    action_name = "修复" if args.fix else "检查"
    print(
        f"\n{action_name}完成: {files_with_issues}/{len(target_files)} 个文件"
        f"有问题, 共 {total_issues} 处"
    )

    if args.check:
        sys.exit(min(total_issues, 127))


def _lint_file(filepath: str, do_fix: bool) -> list[str]:
    """检查（并可选修复格式问题）单个文件，返回问题/变更列表。

    格式问题：do_fix=True 时调 format_org 写盘修复。
    语义问题：始终只报告（不自动改）。
    """
    with open(filepath, "r", encoding="utf-8") as f:
        text = f.read()

    issues: list[str] = []

    # ── 格式问题：调 format_org 做 diff ──
    new_text, fmt_changes = format_org(text, strict=True)
    if fmt_changes:
        # 去重格式变更说明（format_org 可能重复报告同类问题）
        seen = set()
        for ch in fmt_changes:
            key = ch.strip()
            if key not in seen:
                seen.add(key)
                issues.append(ch)
    if do_fix and fmt_changes:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_text)

    # ── 语义问题（始终只报告，--fix 不修）──
    # 用原始 text 检查（语义问题不依赖格式化结果）
    issues += _check_semantic(text)

    return issues


# ═══════════════════════════════════════════════════════════════════════════════
# 语义检查
# ═══════════════════════════════════════════════════════════════════════════════

# fingerprint 行字段数应为 5：:cat:type:owner:tech:entry::
# 即 :END: 后的 :...:: 行，去掉首尾 : 和 :: 后按 : 拆分应得 5 段
_FINGERPRINT_LINE = re.compile(r"^:([^:\s][^:]*(:[^:]+)*?)::\s*$")

# 标准卡片骨架章节（** 二级标题），缺失时提示（信息性，非错误）
_STANDARD_SECTIONS = [
    "** 难点与坑点 :difficulties:",
    "** 经验教训 :lessons:",
    "** AI 建议 :ai_notes:",
]


def _check_semantic(text: str) -> list[str]:
    """检查 agenote 卡片语义问题（不自动修，只报告）。

    检查项：
      1. 缺失 ENTRY_TYPE（agenote 卡片应有，旧卡片可能缺）
      2. TYPE 枚举漂移（不在 VALID_TYPES）
      3. OWNER 枚举漂移（不在 VALID_OWNERS）
      4. ENTRY_TYPE 枚举漂移（不在 VALID_ENTRY_TYPES，且非空）
      5. fingerprint 行字段数 ≠ 5
      6. 缺失标准骨架章节（信息性提示）
    """
    issues: list[str] = []

    # 1. ENTRY_TYPE 缺失
    entry_type = parse_org_prop(text, "ENTRY_TYPE")
    if not entry_type:
        issues.append("  语义: 缺失 :ENTRY_TYPE: 字段（建议补 note/mistake/ascended）")

    # 2. TYPE 枚举
    card_type = parse_org_prop(text, "TYPE")
    if card_type and card_type not in VALID_TYPES:
        issues.append(
            f"  语义: :TYPE: {card_type} 不在 VALID_TYPES（{sorted(VALID_TYPES)}）"
        )

    # 3. OWNER 枚举
    owner = parse_org_prop(text, "OWNER")
    if owner and owner not in VALID_OWNERS:
        issues.append(
            f"  语义: :OWNER: {owner} 不在 VALID_OWNERS（{sorted(VALID_OWNERS)}）"
        )

    # 4. ENTRY_TYPE 枚举（有值时校验）
    if entry_type and entry_type not in VALID_ENTRY_TYPES:
        issues.append(
            f"  语义: :ENTRY_TYPE: {entry_type} 不在 VALID_ENTRY_TYPES"
            f"（{sorted(VALID_ENTRY_TYPES)}）"
        )

    # 5. fingerprint 字段数
    fp_issue = _check_fingerprint_fields(text)
    if fp_issue:
        issues.append(fp_issue)

    # 6. 标准骨架章节（信息性，只在卡片有正文时检查）
    if "** " in text:
        missing_sections = [s for s in _STANDARD_SECTIONS if s not in text]
        if missing_sections:
            issues.append(f"  信息: 缺失标准章节 {missing_sections}（信息性，非必须）")

    return issues


def _check_fingerprint_fields(text: str) -> str | None:
    """检查 fingerprint 行字段数是否为 5。

    fingerprint 格式：:category:type:owner:tech:entry_type::
    去掉首尾的 : 和 :: 后按 : 拆分应得 5 段。
    """
    lines = text.split("\n")
    # 找 :END: 后第一行
    end_idx = None
    for i, ln in enumerate(lines):
        if ln.strip() == ":END:":
            end_idx = i
            break
    if end_idx is None or end_idx + 1 >= len(lines):
        return None

    fp_line = lines[end_idx + 1]
    m = _FINGERPRINT_LINE.match(fp_line)
    if not m:
        return None  # 无 fingerprint 行（旧卡片），不报

    # 解析字段：去掉首 : 和尾 ::，按 : 拆分
    inner = fp_line.strip()
    if inner.startswith(":"):
        inner = inner[1:]
    if inner.endswith("::"):
        inner = inner[:-2]
    fields = inner.split(":")
    if len(fields) != 5:
        return (
            f"  语义: fingerprint 字段数 {len(fields)}（应为 5: "
            f"category:type:owner:tech:entry_type）— {fp_line.strip()}"
        )
    return None


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: inbox — 快速捕获
# ═══════════════════════════════════════════════════════════════════════════════
