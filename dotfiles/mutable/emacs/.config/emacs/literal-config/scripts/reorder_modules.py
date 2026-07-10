#!/usr/bin/env python3
"""Reorganize emacs.org to place module assembly blocks in PLAN.md §4 order.

After migrate_inlines.py appends all modules to end of file, this script:
  1. Extracts each <<module/literal-X>> assembly block + its :noweb-ref tangent-no
     source block from current emacs.org.
  2. For each module, computes insertion position based on PLACEMENT_ORDER
     (a list of (top_section, l2_title, basename) tuples in PLAN.md §4 order).
  3. Writes them into emacs.org in order, in the right section.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORG = os.path.join(ROOT, "emacs.org")

# PLAN.md §4 order:
# bootstrap → frame → (git, color-scheme, tab-line, modeline, help, context-menu, which-key-data)
# → knowledge / agenote → completion → dashboard
# bootstrap and frame are already inlined in head.
PLACEMENT_ORDER = [
    ("界面与外观",     "Git 操作与 display-buffer 路由",     "literal-git"),
    ("界面与外观",     "颜色方案(ef-themes)",                "literal-color-scheme"),
    ("界面与外观",     "Tab-line",                            "literal-tab-line"),
    ("界面与外观",     "Modeline(spaceline)",                 "literal-modeline"),
    ("界面与外观",     "Help 系统",                           "literal-help"),
    ("界面与外观",     "Context menu(右键菜单)",             "literal-context-menu"),
    ("界面与外观",     "Which-key 数据",                      "literal-which-key-data"),
    ("Org 与知识库",   "Knowledge 系统",                      "literal-org-knowledge"),
    ("Org 与知识库",   "agenote",                             "literal-org-agenote"),
    ("键位与补全",     "Completion 框架",                     "literal-completion"),
    ("系统工具与实验性", "Dashboard",                          "literal-dashboard"),
]

def read_org():
    with open(ORG, encoding="utf-8") as f:
        return f.read().splitlines()

def write_org(lines):
    with open(ORG, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

def extract_module_blocks(lines, name):
    """Extract (tangle_no_block_lines, assembly_block_lines) for module/name.

    Returns (tangle_no, assembly) as lists of lines (including begin/end_src).
    None if not found.
    """
    tangle_no = None
    assembly = None
    begin_re = re.compile(r"^\s*#\+begin_src\s+")
    end_line = "#+end_src"
    ref_re = re.compile(r":noweb-ref\s+" + re.escape(f"module/{name}") + r"\b")
    asm_re = re.compile(r"<<module/" + re.escape(name) + r">>")

    i = 0
    while i < len(lines):
        line = lines[i]
        m = begin_re.match(line)
        if m:
            if ref_re.search(line):
                # capture :tangle no block
                block = [line]
                i += 1
                while i < len(lines) and lines[i].strip() != end_line:
                    block.append(lines[i])
                    i += 1
                if i < len(lines):
                    block.append(lines[i])  # end_src
                    i += 1
                tangle_no = block
                continue
            # Check if it's the assembly block (contains <<module/X>>)
            # peek inside
            end = i
            while end < len(lines) and lines[end].strip() != end_line:
                end += 1
            block_text = "\n".join(lines[i:end+1])
            if asm_re.search(block_text):
                assembly = lines[i:end+1]
                i = end + 1
                continue
            i = end + 1
            continue
        i += 1

    return tangle_no, assembly

def remove_module_blocks(lines, name):
    """Remove :noweb-ref and assembly blocks for module/name from lines."""
    out = []
    begin_re = re.compile(r"^\s*#\+begin_src\s+")
    end_line = "#+end_src"
    ref_re = re.compile(r":noweb-ref\s+" + re.escape(f"module/{name}") + r"\b")
    asm_re = re.compile(r"<<module/" + re.escape(name) + r">>")

    i = 0
    while i < len(lines):
        line = lines[i]
        m = begin_re.match(line)
        if m:
            if ref_re.search(line):
                i += 1
                while i < len(lines) and lines[i].strip() != end_line:
                    i += 1
                if i < len(lines):
                    i += 1
                continue
            end = i
            while end < len(lines) and lines[end].strip() != end_line:
                end += 1
            block_text = "\n".join(lines[i:end+1])
            if asm_re.search(block_text):
                i = end + 1
                continue
            out.append(line)
            i += 1
            continue
        out.append(line)
        i += 1
    return out

def find_top_section(lines, top_title):
    for i, line in enumerate(lines):
        m = re.match(r"^\* (.+)$", line)
        if m and m.group(1).strip() == top_title:
            j = i + 1
            while j < len(lines) and not re.match(r"^\* ", lines[j]):
                j += 1
            return i, j
    return None, None

def find_or_make_l2(lines, top_start, top_end, l2_title):
    """Find existing ** l2_title; if not found, append before top_end."""
    for i in range(top_start + 1, top_end):
        m = re.match(r"^\*\* (.+)$", lines[i])
        if m and m.group(1).strip() == l2_title:
            return i
    # Append before top_end
    insertion = top_end
    payload = ["", f"** {l2_title}", "", f"由 emacs.org tangle 时将 =lisp/{l2_title}.el= 内容嵌入 main_el。", ""]
    return insertion, payload

def find_l2_end(lines, l2_start):
    j = l2_start + 1
    while j < len(lines):
        if re.match(r"^\*\* ", lines[j]) or re.match(r"^\* ", lines[j]):
            break
        j += 1
    return j

def main():
    lines = read_org()

    # Extract all module blocks first (before removal).
    extracted = {}
    for top, l2, name in PLACEMENT_ORDER:
        tn, asm = extract_module_blocks(lines, name)
        if tn is None or asm is None:
            print(f"WARN: missing block for {name} (tangle_no={tn is not None} asm={asm is not None})", file=sys.stderr)
        extracted[name] = (tn or [], asm or [])

    # Remove all module blocks from current lines.
    for top, l2, name in PLACEMENT_ORDER:
        lines = remove_module_blocks(lines, name)

    # Re-insert in order.
    for top, l2, name in PLACEMENT_ORDER:
        tn, asm = extracted[name]
        if not tn and not asm:
            continue

        cache_key = top
        top_start, top_end = find_top_section(lines, top)
        if top_start is None:
            print(f"WARN: top {top!r} not found", file=sys.stderr)
            continue

        # Find existing l2 or insert new one
        existing_l2 = None
        for i in range(top_start + 1, top_end):
            m = re.match(r"^\*\* (.+)$", lines[i])
            if m and m.group(1).strip() == l2:
                existing_l2 = i
                break

        if existing_l2 is None:
            # Create new l2 at end of top section
            payload = ["", f"** {l2}", "", f"由 emacs.org tangle 时将 =lisp/{name}.el= 内容嵌入 main_el。", ""]
            lines = lines[:top_end] + payload + lines[top_end:]
            top_start, top_end = find_top_section(lines, top)
            for i in range(top_start + 1, top_end):
                m = re.match(r"^\*\* (.+)$", lines[i])
                if m and m.group(1).strip() == l2:
                    existing_l2 = i
                    break

        # If the l2 already has substantial code (existing_src_in_l2) and
        # the module name is one that MUST be loaded before sibling callers
        # in this top section, we instead prepend the module to the top of
        # the section (before any existing ** subsection).
        # For simplicity, prepend the assembly block immediately after the
        # top-level title + first intro prose.
        prepend_modules = {"literal-git", "literal-help", "literal-tab-line",
                           "literal-modeline", "literal-context-menu",
                           "literal-which-key-data"}
        l2_end = find_l2_end(lines, existing_l2)
        clean_tn = []
        skip = True
        for line in tn:
            if skip and (line.startswith("***") or line.strip().startswith("由 emacs.org")):
                continue
            skip = False
            clean_tn.append(line)
        new_block = [""] + clean_tn + [""] + asm + [""]

        if name in prepend_modules and existing_l2 - top_start > 3:
            # The l2 already exists with substantial sibling content.
            # Prepend module blocks at top of section (before any ** subsection).
            # Insertion point: after top title + first intro paragraph.
            i = top_start + 1
            while i < top_end and lines[i].strip() == "":
                i += 1
            while i < top_end and lines[i].strip() != "" and not re.match(r"^\*\* ", lines[i]):
                i += 1
            lines = lines[:i] + new_block + lines[i:]
        else:
            # Append to l2 end.
            insertion = l2_end
            lines = lines[:insertion] + new_block + lines[insertion:]

    write_org(lines)
    print("Wrote", ORG)

if __name__ == "__main__":
    main()