#!/usr/bin/env python3

# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""修复经验卡片格式问题。

通用规则：
  1. 删除已知空章节标签（难点与坑点、经验教训、相关链接、AI 建议）
  2. 删除执行过程中重复出现的"任务描述"
  3. 将 *** 三级标题转为列表项（通用正则，匹配任何 *** 标题）
  4. 合并多余连续空行
"""

import re
import sys
from pathlib import Path


def fix_card(filepath: Path) -> bool:
    """修复单个卡片的格式问题，返回是否做了修改。"""
    content = filepath.read_text(encoding="utf-8")
    original = content

    # ── 1. 删除空的章节标签 ─────────────────────────────────────────────
    # 这些章节在模板中生成但常留空，清理以减少噪音
    empty_sections = [
        r"\*\* 难点与坑点 :difficulties:\s*\n",
        r"\*\* 经验教训 :lessons:\s*\n",
        r"\*\* 相关链接\s*\n\s*\n",
        r"\*\* AI 建议 :ai_notes:\s*\n\s*\n",
    ]
    for pattern in empty_sections:
        content = re.sub(pattern, "", content)

    # ── 2. 删除执行过程中重复的"任务描述" ──────────────────────────────
    # 如果在 "** 执行过程" 后面紧跟着 "** 任务描述"，删除重复的后者
    content = re.sub(
        r"(\*\* 执行过程\s*\n)\s*\*\* 任务描述\s*\n", r"\1", content
    )

    # ── 3. 将 *** 三级标题转为列表项 ───────────────────────────────────
    # 通用规则：匹配任何 "*** 标题文本" 并转为 "- 标题文本："
    # 这个正则会自动匹配未来新增的三级标题，无需硬编码
    content = re.sub(
        r"^\*\*\*\s+(.+?)\s*$",  # *** 后面的标题文本
        r"- \1：",                # 转为 "- 标题："
        content,
        flags=re.MULTILINE,
    )

    # ── 4. 合并多余连续空行 ───────────────────────────────────────────
    content = re.sub(r"\n{3,}", "\n\n", content)

    if content != original:
        filepath.write_text(content, encoding="utf-8")
        return True
    return False


def main() -> int:
    """遍历所有经验卡片并修复格式问题。"""
    experiences_dir = Path.home() / "Documents" / "Org" / "experiences"
    if not experiences_dir.is_dir():
        print(f"经验卡片目录不存在: {experiences_dir}", file=sys.stderr)
        return 1

    fixed = []
    for org_file in experiences_dir.rglob("*.org"):
        if org_file.is_symlink():
            continue
        if fix_card(org_file):
            fixed.append(org_file.name)

    print(f"修复了 {len(fixed)} 个文件：")
    for name in fixed:
        print(f"  - {name}")

    if not fixed:
        print("没有需要修复的文件")

    return 0


if __name__ == "__main__":
    sys.exit(main())
