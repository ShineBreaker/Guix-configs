# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""orgfmt — 通用 org-mode 格式化核心。

零内部依赖（仅标准库），既被独立 `orgfmt` CLI 使用，也被 agenote import。
所有函数纯函数化，format_org() 幂等（连续跑两次第二次无变更）。

设计分层：
  - 通用规则（默认）：属性列对齐、block 大小写、affiliated keyword 紧贴、
    空行规范化、行内标记 PRE/POST 间距、表格列对齐
  - strict 规则（agenote 卡片专用）：Markdown→Org 6 条转换、fingerprint 尾随空格

管线顺序（format_org 内）：
  1. _normalize_blocks      — block 大小写统一（建立状态机，供后续阶段跳过代码块）
  2. _md_to_org             — [strict] Markdown→Org 转换（需在非代码块内）
  3. _fix_inline_markers    — 行内标记 PRE/POST 间距
  4. _align_properties      — :PROPERTIES: drawer 列对齐
  5. _normalize_fingerprint — [strict] fingerprint 行尾随空格
  6. _fix_affiliated        — affiliated keyword 紧贴 block
  7. _align_tables          — 表格列对齐（CJK 宽度）
  8. _normalize_blank_lines — 空行规则（最后跑，基于已规范化的结构）
"""

import re
import unicodedata
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# 公开接口
# ═══════════════════════════════════════════════════════════════════════════════


def format_org(text: str, *, strict: bool = False) -> tuple[str, list[str]]:
    """格式化 org 文本，返回 (新文本, 变更说明列表)。幂等。

    Args:
        text: org 文件全文
        strict: 启用 agenote 卡片专用规则（MD→Org、fingerprint 清理）
    """
    changes: list[str] = []

    text, c = _normalize_blocks(text)
    changes += c

    if strict:
        text, c = _md_to_org(text)
        changes += c

    text, c = _fix_inline_markers(text)
    changes += c

    text, c = _align_properties(text)
    changes += c

    if strict:
        text, c = _normalize_fingerprint(text)
        changes += c

    text, c = _fix_affiliated(text)
    changes += c

    text, c = _align_tables(text)
    changes += c

    text, c = _normalize_blank_lines(text)
    changes += c

    return text, changes


def format_file(
    path: str | Path, *, strict: bool = False, dry_run: bool = False
) -> list[str]:
    """格式化单个文件，返回变更说明列表。

    Args:
        path: 文件路径
        strict: 启用 agenote 专用规则
        dry_run: True 只检查不写盘
    """
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    new_text, changes = format_org(text, strict=strict)
    if changes and not dry_run:
        p.write_text(new_text, encoding="utf-8")
    return changes


def cmd_format(args, ctx=None) -> None:
    """agenote format 子命令：格式化卡片（默认直接写盘）。

    agenote 域默认 strict=True（一次完成全部可自动化的格式化）。
    --check 只检查不写盘；目标文件缺省时扫全部 experiences。
    """
    import argparse  # 局部 import，避免顶层依赖

    # 延迟 import ctx，避免 orgfmt.py 顶层依赖 ag_lib.core（保持零内部依赖）
    if ctx is None:
        from ag_lib.core import default_context

        ctx = default_context()

    target_files = getattr(args, "files", None) or []
    if not target_files:
        target_files = sorted(
            str(f) for f in ctx.experiences.rglob("*.org") if not f.is_symlink()
        )
    if not target_files:
        print("未找到 .org 文件")
        return

    do_check = getattr(args, "check", False)
    total_changes = 0
    files_changed = 0
    for filepath in target_files:
        try:
            changes = format_file(filepath, strict=True, dry_run=do_check)
        except OSError as e:
            print(f"错误 {filepath}: {e}", file=__import__("sys").stderr)
            continue
        if changes:
            total_changes += len(changes)
            files_changed += 1
            import os

            basename = os.path.basename(filepath)
            print(f"\n{basename} ({len(changes)} 项):")
            for ch in changes:
                print(ch)

    action = "检查" if do_check else "格式化"
    print(
        f"\n{action}完成: {files_changed}/{len(target_files)} 个文件有变更, "
        f"共 {total_changes} 处"
    )


# ═══════════════════════════════════════════════════════════════════════════════
# 辅助：CJK 显示宽度
# ═══════════════════════════════════════════════════════════════════════════════


def _disp_width(s: str) -> int:
    """计算字符串的显示宽度（CJK 全角字符算 2 列）。"""
    w = 0
    for ch in s:
        if unicodedata.east_asian_width(ch) in ("W", "F"):
            w += 2
        else:
            w += 1
    return w


# ═══════════════════════════════════════════════════════════════════════════════
# 代码块 / block 识别（跨阶段共享的状态机辅助）
# ═══════════════════════════════════════════════════════════════════════════════

# 匹配 #+begin_src / #+begin_example / #+begin_quote 等所有 block 起始
_BLOCK_BEGIN = re.compile(r"^(\s*)#\+begin_(\w+)\b", re.IGNORECASE)
_BLOCK_END = re.compile(r"^(\s*)#\+end_(\w+)\b", re.IGNORECASE)
# Markdown ``` 围栏（strict 模式下会被转成 block）
_MD_FENCE = re.compile(r"^(\s*)```(\w*)\s*$")


def _iter_lines_with_block_state(text: str):
    """逐行生成 (行内容, 行号, in_block)。

    in_block 标记该行是否位于 #+begin_src/.../#+end_src 或 ``` 围栏内部。
    围栏起始行本身 in_block=False（它是边界），围栏内内容 True。
    """
    in_org = False
    in_md = False
    for i, line in enumerate(text.split("\n")):
        if _BLOCK_BEGIN.match(line):
            in_org = True
            yield line, i, False
            continue
        if _BLOCK_END.match(line):
            in_org = False
            yield line, i, False
            continue
        if _MD_FENCE.match(line):
            # 围栏是边界切换：第一次进入，第二次退出
            in_md = not in_md
            yield line, i, False
            continue
        yield line, i, in_org or in_md


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 1：block 大小写统一
# ═══════════════════════════════════════════════════════════════════════════════


def _normalize_blocks(text: str) -> tuple[str, list[str]]:
    """统一 #+begin_xxx / #+end_xxx 为小写（Org 惯例）。

    例：#+BEGIN_SRC python → #+begin_src python
    保留 #+begin_ 后的参数（语言、switches、header args）原样，只规范化关键字大小写。
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []

    for i, line in enumerate(lines):
        new = line
        m = _BLOCK_BEGIN.match(line)
        if m:
            indent, _btype = m.group(1), m.group(2).lower()
            # 重写为 #+begin_<type>（小写），保留 indent 与后续参数
            rest = line[m.end() :]  # #+begin_src 之后的全部内容（含语言名）
            new = f"{indent}#+begin_{_btype}{rest}"
        else:
            m = _BLOCK_END.match(line)
            if m:
                indent = m.group(1)
                btype = m.group(2).lower()
                rest = line[m.end() :]
                new = f"{indent}#+end_{btype}{rest}"

        if new != line:
            changes.append(f"  行 {i + 1}: block 关键字大小写 → 小写")
        result.append(new)

    return "\n".join(result), changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 2 [strict]：Markdown → Org 转换（迁移自 lint.py）
# ═══════════════════════════════════════════════════════════════════════════════


def _md_to_org(text: str) -> tuple[str, list[str]]:
    """Markdown 残留语法转 Org（仅在非代码块内）。

    迁移自 lint.py 的 6 条规则。与原实现保持行为一致。
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []
    in_code_block = False  # 追踪 ``` 代码块状态
    in_org_code_block = False  # 追踪 #+begin_src ... #+end_src 代码块状态

    i = 0
    while i < len(lines):
        line = lines[i]

        # ── 规则 1: ```lang ... ``` → #+begin_src lang ... #+end_src ──
        code_match = _MD_FENCE.match(line)
        if code_match:
            indent = code_match.group(1)
            lang = code_match.group(2)
            if not in_code_block:
                in_code_block = True
                new_line = f"{indent}#+begin_src {lang}".rstrip()
                if new_line != line:
                    changes.append(f"  行 {i + 1}: ```{lang} → #+begin_src {lang}")
                result.append(new_line)
                i += 1
                continue
            else:
                in_code_block = False
                new_line = f"{indent}#+end_src"
                changes.append(f"  行 {i + 1}: ``` → #+end_src")
                result.append(new_line)
                i += 1
                continue

        # ── 追踪 Org 代码块状态 ──
        if _BLOCK_BEGIN.match(line):
            in_org_code_block = True
        elif _BLOCK_END.match(line):
            in_org_code_block = False

        # ── 规则 2-5: 只在非代码块内生效 ──
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
                changes.append(f"  行 {i + 1}: **bold** → *bold*")
                line = new_line

            # Markdown heading → Org heading
            heading_match = re.match(r"^(#{1,6})\s+(.+)$", line)
            if heading_match:
                level = len(heading_match.group(1)) + 1
                title = heading_match.group(2)
                new_line = f"{'*' * level} {title}"
                changes.append(f"  行 {i + 1}: Markdown heading → Org heading")
                line = new_line

            # `- list` → `+ list`
            list_match = re.match(r"^(\s*)(- )(\S)", line)
            if list_match and not line.lstrip().startswith("--"):
                indent = list_match.group(1)
                content = line.lstrip()[2:]
                new_line = f"{indent}+ {content}"
                changes.append(f"  行 {i + 1}: `- ` → `+ `")
                line = new_line

            # `inline code` → ~inline code~
            if "`" in line and "```" not in line:
                new_line = re.sub(r"`([^`\n]+?)`", r"~\1~", line)
                if new_line != line:
                    count = len(re.findall(r"`[^`\n]+?`", line))
                    changes.append(f"  行 {i + 1}: `code` → ~code~ (×{count})")
                    line = new_line

        result.append(line)
        i += 1

    return "\n".join(result), changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 3：行内标记 PRE/POST 间距（迁移自 lint.py）
# ═══════════════════════════════════════════════════════════════════════════════

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
        if (
            start > 0
            and line[start - 1] not in _MARKER_PRE_VALID
            and line[start - 1] != marker_char
        ):
            if not any(pos == start for pos, _ in inserts):
                inserts.append((start, " "))
                pre_count += 1

        if end < len(line) and line[end] not in _MARKER_POST_VALID:
            if not any(pos == end for pos, _ in inserts):
                inserts.append((end, " "))
                post_count += 1

    if not inserts:
        return line, 0, 0

    result = list(line)
    for pos, char in sorted(inserts, reverse=True):
        result.insert(pos, char)

    return "".join(result), pre_count, post_count


def _fix_inline_markers(text: str) -> tuple[str, list[str]]:
    """对全文非代码块行应用 ~...~ / *...* 标记的 PRE/POST 间距修复。"""
    changes: list[str] = []
    result = []

    for line, idx, in_block in _iter_lines_with_block_state(text):
        if in_block:
            result.append(line)
            continue
        # 跳过 Org 标题行（* 开头）避免误伤
        if re.match(r"^\*+\s", line):
            result.append(line)
            continue

        new_line = line
        if "~" in new_line:
            new_line, pre_n, post_n = _fix_marker_spacing(new_line, "~")
            if pre_n:
                changes.append(f"  行 {idx + 1}: ~code~ 前缺空格 (×{pre_n})")
            if post_n:
                changes.append(f"  行 {idx + 1}: ~code~ 后缺空格 (×{post_n})")

        if "*" in new_line:
            new_line, pre_n, post_n = _fix_marker_spacing(new_line, "*")
            if pre_n:
                changes.append(f"  行 {idx + 1}: *bold* 前缺空格 (×{pre_n})")
            if post_n:
                changes.append(f"  行 {idx + 1}: *bold* 后缺空格 (×{post_n})")

        result.append(new_line)

    return "\n".join(result), changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 4：属性 drawer 列对齐
# ═══════════════════════════════════════════════════════════════════════════════

# 匹配 drawer 内的属性行：:KEY:   value  或  :KEY:
_PROP_LINE = re.compile(r"^:(\w+):(\s*)(.*)$")


def _align_properties(text: str) -> tuple[str, list[str]]:
    """对齐 :PROPERTIES: ... :END: drawer 内的属性列。

    规则：
    - 所有 :KEY: 的值起始列对齐到 drawer 内最长 KEY + 1 空格
    - 空值字段（如 :EFFORT:）保持无尾随空格
    - 只作用于 :PROPERTIES: drawer（其他 drawer 如 :LOGBOOK: 不动）

    例：
      :ID:       20260701-120000
      :ENTRY_TYPE: note
      →
      :ID:         20260701-120000
      :ENTRY_TYPE: note
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]
        # 检测 :PROPERTIES: drawer 起始
        if line.strip() == ":PROPERTIES:":
            drawer_start = i
            drawer_lines = [line]
            j = i + 1
            # 收集 drawer 内行直到 :END:
            while j < len(lines) and lines[j].strip() != ":END:":
                drawer_lines.append(lines[j])
                j += 1
            if j < len(lines):  # 找到 :END:
                drawer_lines.append(lines[j])  # :END: 行
                aligned, n = _align_one_drawer(drawer_lines, drawer_start)
                changes += n
                result.extend(aligned)
                i = j + 1
                continue
            else:
                # 未闭合 drawer，原样输出
                result.extend(drawer_lines)
                i = j
                continue
        else:
            result.append(line)
            i += 1

    return "\n".join(result), changes


def _align_one_drawer(
    drawer_lines: list[str], base_idx: int
) -> tuple[list[str], list[str]]:
    """对齐单个 drawer 的属性行（drawer_lines 含 :PROPERTIES: 和 :END:）。"""
    changes: list[str] = []
    # 解析每行：是否为属性行、key、原始值
    parsed = []  # [(原行, 是否属性, key, 值)]
    max_key_len = 0
    for ln in drawer_lines:
        m = _PROP_LINE.match(ln)
        if ln.strip() in (":PROPERTIES:", ":END:"):
            parsed.append((ln, False, None, None))
            continue
        if m:
            key = m.group(1)
            val = m.group(3).rstrip()  # 去尾随空格
            parsed.append((ln, True, key, val))
            if len(key) > max_key_len:
                max_key_len = len(key)
        else:
            # drawer 内非属性行（少见），原样保留
            parsed.append((ln, False, None, None))

    # 生成对齐后的行：":KEY:" + 空格补齐到 max_key_len + 1 个空格 + 值
    result = []
    for orig, is_prop, key, val in parsed:
        if is_prop:
            # 空值：":KEY:" 无尾随空格
            if not val:
                new = f":{key}:"
            else:
                # 对齐：":KEY:" + (max_key_len - len(key) + 1) 个空格 + 值
                pad = max_key_len - len(key) + 1
                new = f":{key}:" + (" " * pad) + val
            if new != orig:
                changes.append(f"  行 {base_idx + len(result) + 1}: 属性 :{key}: 对齐")
            result.append(new)
        else:
            result.append(orig)

    return result, changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 5 [strict]：fingerprint 行尾随空格清理
# ═══════════════════════════════════════════════════════════════════════════════

# fingerprint 行：:cat:type:owner:tech:entry:: （以 : 开头、:: 结尾、含字段）
# tech 字段可能含分号、连字符等，故用宽松字符类（排除空格与下一个 : 的歧义）
_FINGERPRINT = re.compile(r"^(:[^:\s][^:]*(:[^:]+)*::)\s*$")


def _normalize_fingerprint(text: str) -> tuple[str, list[str]]:
    """清理卡片 fingerprint 行（:END: 后的 :cat:type:owner:tech:entry::）的尾随空格。

    不改字段值（字段数校验留给 lint），只保证格式干净：去尾随空格、确保 :: 结尾。
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []
    saw_end = False

    for i, line in enumerate(lines):
        new = line
        if line.strip() == ":END:":
            saw_end = True
            result.append(line)
            continue
        if saw_end and _FINGERPRINT.match(line):
            # 去尾随空格
            stripped = line.rstrip()
            if stripped != line:
                changes.append(f"  行 {i + 1}: fingerprint 行尾随空格")
            new = stripped
            saw_end = False  # 只处理 :END: 后第一行
        else:
            # 其他行重置 saw_end（避免误判非 drawer 的 :END:）
            if line.strip() != ":END:":
                saw_end = False
        result.append(new)

    return "\n".join(result), changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 6：affiliated keywords 紧贴 block
# ═══════════════════════════════════════════════════════════════════════════════

# affiliated keywords：必须紧贴下方 #+begin_* block
_AFFILIATED = re.compile(
    r"^[ \t]*#\+(name|caption|attr_\w+|header|plot|results|label|orphan|toc|include)\b",
    re.IGNORECASE,
)


def _fix_affiliated(text: str) -> tuple[str, list[str]]:
    """删除 affiliated keyword 与下方 #+begin_* block 之间的空行。

    #+name: / #+caption: / #+attr_html: 等 affiliated keywords 必须紧贴 block，
    二者间的空行会导致 Org 不识别 affiliation。

    上方空行保留（与上文段落分隔）。
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []
    i = 0

    while i < len(lines):
        result.append(lines[i])
        # 若当前行是 affiliated keyword，跳过其后连续空行直到非空行
        if _AFFILIATED.match(lines[i]):
            j = i + 1
            removed = 0
            while j < len(lines) and lines[j].strip() == "":
                removed += 1
                j += 1
            if removed > 0:
                changes.append(
                    f"  行 {i + 2}: affiliated keyword 与 block 间空行（删除 {removed} 行）"
                )
            i = j
        else:
            i += 1

    return "\n".join(result), changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 7：表格列对齐
# ═══════════════════════════════════════════════════════════════════════════════

# 表格行：以 | 开头（允许前导空白）
_TABLE_ROW = re.compile(r"^[ \t]*\|.*\|[ \t]*$")
# 表格分隔行：|---|---| 或 |---+---|
_TABLE_SEP = re.compile(r"^[ \t]*\|[-+|]+\|[ \t]*$")


def _align_tables(text: str) -> tuple[str, list[str]]:
    """对齐 org 表格列宽（支持 CJK 全角字符）。

    连续的表格行块统一对齐：每列宽度取该列最大显示宽度 + 1 空格 padding。
    分隔行（|---+---|）重新生成以匹配新列宽。
    """
    changes: list[str] = []
    lines = text.split("\n")
    result = []
    i = 0

    while i < len(lines):
        if _TABLE_ROW.match(lines[i]) and not _TABLE_SEP.match(lines[i]):
            # 收集连续表格行块
            block_start = i
            block = []
            while i < len(lines) and _TABLE_ROW.match(lines[i]):
                block.append(lines[i])
                i += 1
            aligned, n = _align_one_table(block, block_start)
            changes += n
            result.extend(aligned)
        else:
            result.append(lines[i])
            i += 1

    return "\n".join(result), changes


def _parse_table_row(line: str) -> list[str]:
    """解析表格行为单元格列表（去除外层 | 与首尾空白）。"""
    s = line.strip()
    # 去掉首尾 |
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [cell.strip() for cell in s.split("|")]


def _align_one_table(block: list[str], base_idx: int) -> tuple[list[str], list[str]]:
    """对齐单个表格块。返回 (新行列表, 变更说明)。"""
    changes: list[str] = []
    # 解析每行
    rows = []  # [(原始行, 单元格列表, 是否分隔行)]
    for ln in block:
        if _TABLE_SEP.match(ln):
            rows.append((ln, None, True))
        else:
            rows.append((ln, _parse_table_row(ln), False))

    # 计算每列最大显示宽度
    n_cols = max(
        (len(cells) for _, cells, is_sep in rows if cells is not None), default=0
    )
    if n_cols == 0:
        return block, []

    col_widths = [0] * n_cols
    for _, cells, is_sep in rows:
        if cells is None:
            continue
        for c in range(min(len(cells), n_cols)):
            w = _disp_width(cells[c])
            if w > col_widths[c]:
                col_widths[c] = w

    # 生成对齐后的行
    result = []
    for idx, (orig, cells, is_sep) in enumerate(rows):
        if is_sep:
            # 分隔行：|-------+-------|
            sep_cells = ["-" * (w + 2) for w in col_widths]
            new = "|" + "+".join(sep_cells) + "|"
        else:
            # 数据行：左对齐，每格 " content " + 补空格
            parts = []
            for c in range(n_cols):
                val = cells[c] if c < len(cells) else ""
                pad = col_widths[c] - _disp_width(val)
                parts.append(" " + val + " " * (pad + 1))
            new = "|" + "|".join(parts) + "|"
        if new != orig:
            changes.append(f"  行 {base_idx + idx + 1}: 表格列对齐")
        result.append(new)

    return result, changes


# ═══════════════════════════════════════════════════════════════════════════════
# 阶段 8：空行规范化（最后跑）
# ═══════════════════════════════════════════════════════════════════════════════

_HEADING = re.compile(r"^\*+\s")
_DRAWER_BEGIN = re.compile(r"^\s*:PROPERTIES:\s*$")
_DRAWER_END = re.compile(r"^\s*:END:\s*$")


def _normalize_blank_lines(text: str) -> tuple[str, list[str]]:
    """规范化空行。

    规则：
    - 连续空行折叠为 1
    - 标题（*+ ）前需 1 空行（文件首个标题除外）
    - block 前后需 1 空行
    - drawer 前后需 1 空行
    - 表格前后需 1 空行
    - affiliated keyword 与紧邻的 block 间无空行（由 _fix_affiliated 保证）
    - 文件末尾恰好 1 个换行符
    """
    changes: list[str] = []
    lines = text.split("\n")

    # 先折叠连续空行 + 记录每行"类型"（用于决定空行需求）
    # 第一遍：折叠连续空行
    folded = []
    prev_blank = False
    for ln in lines:
        is_blank = ln.strip() == ""
        if is_blank and prev_blank:
            continue  # 跳过连续空行
        folded.append(ln)
        prev_blank = is_blank

    # 第二遍：确定每个"块边界"需要的空行
    # 块类型：heading / block_begin / block_end / drawer_begin / drawer_end / table / affiliated / normal
    # 表格行按连续 run 分组：run 的首行需前方空行，run 内部行不插空行。
    result = []
    prev_kind = None
    for idx, ln in enumerate(folded):
        if _HEADING.match(ln):
            kind = "heading"
        elif _BLOCK_BEGIN.match(ln):
            kind = "block_begin"
        elif _BLOCK_END.match(ln):
            kind = "block_end"
        elif _DRAWER_BEGIN.match(ln):
            kind = "drawer_begin"
        elif _DRAWER_END.match(ln):
            kind = "drawer_end"
        elif _TABLE_ROW.match(ln):
            kind = "table"
        elif _AFFILIATED.match(ln):
            kind = "affiliated"
        else:
            kind = "normal"

        # 判断前面是否需要空行
        need_blank_before = False
        if idx > 0:
            prev = folded[idx - 1]
            prev_blank = prev.strip() == ""
            if not prev_blank:
                # 当前是结构性块，且前一行非空 → 需要空行分隔
                # 但表格 run 内部（prev 也是 table）不插空行
                if kind == "table" and prev_kind == "table":
                    need_blank_before = False
                elif kind in ("heading", "block_begin", "drawer_begin", "table"):
                    need_blank_before = True
                # block_end / drawer_end / table 后接非空内容也需空行（在第三遍处理）

        if need_blank_before:
            result.append("")
        result.append(ln)
        prev_kind = kind

    # 第三遍：处理"结构块结束后接非空内容"需空行（反向检查）
    # 例：#+end_src 后直接接文字 → 需空行
    # 特例：:END: 后紧接 fingerprint 行（:cat:type:owner:tech:entry::）时保持紧贴，
    # fingerprint 行视为 drawer 元数据的一部分，二者间不插空行；fingerprint 行之后才需空行。
    final = []
    for idx, ln in enumerate(result):
        final.append(ln)
        if _BLOCK_END.match(ln) or _TABLE_ROW.match(ln):
            # 查找下一非空行
            nxt_idx = idx + 1
            if _TABLE_ROW.match(ln):
                # 如果下一行还是表格，不插空行
                if nxt_idx < len(result) and _TABLE_ROW.match(result[nxt_idx]):
                    continue
            if nxt_idx < len(result):
                nxt = result[nxt_idx]
                if nxt.strip() != "" and not _TABLE_ROW.match(nxt):
                    if _AFFILIATED.match(nxt):
                        continue
                    final.append("")
        elif _DRAWER_END.match(ln):
            # :END: 后特判：若下一非空行是 fingerprint，保持紧贴
            nxt_idx = idx + 1
            if nxt_idx < len(result):
                nxt = result[nxt_idx]
                if _FINGERPRINT.match(nxt):
                    continue  # fingerprint 紧贴 :END:，不插空行
                if nxt.strip() != "" and not _TABLE_ROW.match(nxt):
                    if _AFFILIATED.match(nxt):
                        continue
                    final.append("")
        elif _FINGERPRINT.match(ln):
            # fingerprint 行后需空行（与正文 ** 标题分隔）
            nxt_idx = idx + 1
            if nxt_idx < len(result):
                nxt = result[nxt_idx]
                if nxt.strip() != "":
                    final.append("")

    # 去尾随空行 + 确保恰好 1 个换行
    out_lines = final
    while out_lines and out_lines[-1].strip() == "":
        out_lines.pop()
    out_lines.append("")  # 末尾换行（join 后产生 \n）

    new_text = "\n".join(out_lines)
    if new_text != text:
        # 粗粒度记录（细粒度在上面的 append 处）
        changes.append("  空行规范化")

    return new_text, changes
