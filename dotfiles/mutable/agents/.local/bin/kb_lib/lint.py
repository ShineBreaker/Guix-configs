# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_lint — 知识库格式校验与修复：Markdown 残留检测、Org 标记修复"""

import argparse
import os
import re
import sys

from kb_lib.core import KB_EXPERIENCES, die

# ═══════════════════════════════════════════════════════════════════════════════
# lint 命令 — 格式校验与修复
# ═══════════════════════════════════════════════════════════════════════════════


def cmd_lint(args: argparse.Namespace) -> None:
    """
    检测 Org 文件中的 Markdown 残留语法，自动修复为正确的 Org 格式。

    修复项:
      1. ```lang ... ``` → #+begin_src lang ... #+end_src
      2. **bold**        → *bold* (排除 Org 标题)
      3. #/## heading    → **/*** heading
      4. - list item     → + list item
      5. `inline code`   → ~inline code~
      6. Org 行内标记(~code~ / *bold*)外部空格检查与修复
    """
    target_files = args.files
    if not target_files:
        target_files = sorted(
            f for f in KB_EXPERIENCES.rglob("*.org") if not f.is_symlink()
        )
        target_files = [str(p) for p in target_files]

    if not target_files:
        die("未找到 .org 文件")

    total_issues = 0
    files_with_issues = 0

    for filepath in target_files:
        fixes = _lint_file(filepath, do_fix=args.fix)
        if fixes:
            total_issues += len(fixes)
            files_with_issues += 1
            basename = os.path.basename(filepath)
            print(f"\n{basename} ({len(fixes)} 项):")
            for fix in fixes:
                print(fix)

    action_name = "修复" if args.fix else "检查"
    print(
        f"\n{action_name}完成: {files_with_issues}/{len(target_files)} 个文件"
        f"有 Markdown 残留, 共 {total_issues} 处"
    )

    if args.check:
        sys.exit(min(total_issues, 127))


def _lint_file(filepath: str, do_fix: bool) -> list[str]:
    """检查（并可选修复）单个文件，返回修复项列表。"""
    with open(filepath, "r", encoding="utf-8") as f:
        text = f.read()

    new_text, fixes = _fix_org_content(text)

    if do_fix and fixes:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_text)

    return fixes


# Org 强调标记 PRE 合法字符（行首也合法）
_MARKER_PRE_VALID = set(" \t\n({['\"`")
# Org 强调标记 POST 合法字符（行尾也合法）
_MARKER_POST_VALID = set(' \t\n.,:;!?\'"" )}]\\-')


def _fix_marker_spacing(line: str, marker_char: str) -> tuple[str, int, int]:
    """检查并修复 ~...~ 或 *...* 标记的外部空格。

    使用 Org 的 PRE/POST 规则判断是否需要插入空格。
    相邻标记共享边界空格，避免重复插入。

    Returns (fixed_line, pre_fix_count, post_fix_count).
    """
    escaped = re.escape(marker_char)
    pattern = escaped + r"[^" + escaped + r"\n]+" + escaped
    # 过滤纯空白内容的无意义标记（如 ~ ~）
    markers = [
        (m.start(), m.end())
        for m in re.finditer(pattern, line)
        if m.group()[1:-1].strip()
    ]

    if not markers:
        return line, 0, 0

    inserts: list[tuple[int, str]] = []
    pre_count = 0
    post_count = 0

    for start, end in markers:
        # PRE: 标记前需合法字符或行首；跳过标记字符本身（处理 ~~path~ 嵌套）
        if (
            start > 0
            and line[start - 1] not in _MARKER_PRE_VALID
            and line[start - 1] != marker_char
        ):
            if not any(pos == start for pos, _ in inserts):
                inserts.append((start, " "))
                pre_count += 1

        # POST: 标记后需合法字符或行尾
        if end < len(line) and line[end] not in _MARKER_POST_VALID:
            if not any(pos == end for pos, _ in inserts):
                inserts.append((end, " "))
                post_count += 1

    if not inserts:
        return line, 0, 0

    # 从右往左插入，避免位置偏移
    result = list(line)
    for pos, char in sorted(inserts, reverse=True):
        result.insert(pos, char)

    return "".join(result), pre_count, post_count


def _fix_org_content(text: str) -> tuple[str, list[str]]:
    """
    修复 Org 文件中的 Markdown 语法。

    返回 (修复后文本, 修复项列表)。
    逐行处理，跟踪代码块状态以避免误修复代码块内的内容。
    """
    fixes = []
    lines = text.split("\n")
    result = []
    in_code_block = False  # 追踪 ``` 代码块状态
    in_org_code_block = False  # 追踪 #+begin_src ... #+end_src 代码块状态
    i = 0

    while i < len(lines):
        line = lines[i]

        # ── 修复 1: ```lang ... ``` → #+begin_src lang ... #+end_src ──
        code_match = re.match(r"^(\s*)```(\w*)\s*$", line)
        if code_match:
            indent = code_match.group(1)
            lang = code_match.group(2)
            if not in_code_block:
                # 开始代码块
                in_code_block = True
                new_line = f"{indent}#+begin_src {lang}".rstrip()
                if new_line != line:
                    fixes.append(f"  行 {i+1}: ```{lang} → #+begin_src {lang}")
                result.append(new_line)
                i += 1
                continue
            else:
                # 结束代码块
                in_code_block = False
                new_line = f"{indent}#+end_src"
                fixes.append(f"  行 {i+1}: ``` → #+end_src")
                result.append(new_line)
                i += 1
                continue

        # ── 追踪 Org 代码块状态 ──
        if re.match(r"^\s*#\+begin_src\b", line, re.IGNORECASE):
            in_org_code_block = True
        elif re.match(r"^\s*#\+end_src\b", line, re.IGNORECASE):
            in_org_code_block = False

        # ── 修复 2-5: 只在非代码块内生效 ──
        if not in_code_block and not in_org_code_block:
            stripped = line.lstrip()

            # 排除 Org 标题模式（** 或 *** 开头后跟空格）
            if re.match(r"^\*+\s", stripped):
                result.append(line)
                i += 1
                continue

            # 行内 **bold** → *bold*
            new_line = re.sub(r"\*\*(.+?)\*\*", r"*\1*", line)
            if new_line != line:
                fixes.append(f"  行 {i+1}: **bold** → *bold*")
                line = new_line

            # Markdown heading → Org heading
            heading_match = re.match(r"^(#{1,6})\s+(.+)$", line)
            if heading_match:
                level = len(heading_match.group(1)) + 1
                title = heading_match.group(2)
                new_line = f"{'*' * level} {title}"
                fixes.append(f"  行 {i+1}: Markdown heading → Org heading")
                line = new_line

            # `- list` → `+ list`
            list_match = re.match(r"^(\s*)(- )(\S)", line)
            if list_match and not line.lstrip().startswith("--"):
                indent = list_match.group(1)
                content = line.lstrip()[2:]
                new_line = f"{indent}+ {content}"
                fixes.append(f"  行 {i+1}: `- ` → `+ `")
                line = new_line

            # `inline code` → ~inline code~
            if "`" in line and "```" not in line:

                def replace_inline_code(m: re.Match) -> str:
                    return f"~{m.group(1)}~"

                new_line = re.sub(r"`([^`\n]+?)`", replace_inline_code, line)
                if new_line != line:
                    count = len(re.findall(r"`[^`\n]+?`", line))
                    fixes.append(f"  行 {i+1}: `code` → ~code~ (×{count})")
                    line = new_line

            # ── 修复 6: Org 行内标记(~...~ 和 *...*)外部空格 ──
            # Org 强调标记外部需满足 PRE/POST 条件才能渲染
            # PRE: 空格/({[/'"/`/行首  POST: 空格/.,:;!?'" )}]/\/-/行尾
            # 不满足时自动插入空格，相邻标记共享边界空格

            if "~" in line:
                line, pre_n, post_n = _fix_marker_spacing(line, "~")
                if pre_n:
                    fixes.append(f"  行 {i+1}: ~code~ 前缺空格 (×{pre_n})")
                if post_n:
                    fixes.append(f"  行 {i+1}: ~code~ 后缺空格 (×{post_n})")

            if "*" in line:
                line, pre_n, post_n = _fix_marker_spacing(line, "*")
                if pre_n:
                    fixes.append(f"  行 {i+1}: *bold* 前缺空格 (×{pre_n})")
                if post_n:
                    fixes.append(f"  行 {i+1}: *bold* 后缺空格 (×{post_n})")

        result.append(line)
        i += 1

    return "\n".join(result), fixes


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: inbox — 快速捕获
# ═══════════════════════════════════════════════════════════════════════════════
