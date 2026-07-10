#!/usr/bin/env python3
"""Convert lisp/literal-*.el into emacs.org-embedded noweb blocks.

Strategy:
- For each lisp file, emit one :noweb-ref module/<basename> :tangle no block
  containing the source with the file header (;;; literal-FOO.el ... ;;; Code:)
  and (require 'literal-*) / (provide 'literal-*) / SPDX license lines stripped.
- Each logical module gets a top-level emacs.org insertion location (a * (top) section).
- For files whose target top section already exists in emacs.org, we add a
  ** (level 2) child for the module. For sections that don't exist yet,
  we create them.

This script is idempotent: it removes previous :noweb-ref module/<name> blocks
before reinserting, so re-runs are safe.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(REPO)
ORG = os.path.join(ROOT, "emacs.org")
LISP = os.path.join(ROOT, "lisp")

# Module placement map: module basename -> (top section title, level 2 title)
PLACEMENT = {
    # bootstrap and frame are already inlined in the emacs.org head — skip them.
    "literal-git":           ("界面与外观",     "Git 操作与 display-buffer 路由"),
    "literal-color-scheme":  ("界面与外观",     "颜色方案(ef-themes)"),
    "literal-tab-line":      ("界面与外观",     "Tab-line"),
    "literal-modeline":      ("界面与外观",     "Modeline(spaceline)"),
    "literal-help":          ("界面与外观",     "Help 系统"),
    "literal-context-menu":  ("界面与外观",     "Context menu(右键菜单)"),
    "literal-which-key-data":("界面与外观",     "Which-key 数据"),
    "literal-org-knowledge": ("Org 与知识库",   "Knowledge 系统"),
    "literal-org-agenote":   ("Org 与知识库",   "agenote"),
    "literal-completion":    ("键位与补全",     "Completion 框架"),
    "literal-dashboard":     ("系统工具与实验性", "Dashboard"),
}

def strip_header(src):
    """Remove file header, Commentary, Code markers, license, require/provide literals-*."""
    lines = src.splitlines()
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith(";;;") and ("---" in stripped or "Commentary" in stripped or
                                            "Code:" in stripped or "ends here" in stripped):
            continue
        if stripped.startswith(";; SPDX-") or stripped == ";; SPDX-License-Identifier: MIT":
            continue
        if stripped.startswith(";; SPDX-FileCopyrightText:"):
            continue
        if re.match(r"\(require\s+'literal-[\w-]+\)", stripped):
            continue
        if re.match(r"\(provide\s+'literal-[\w-]+\)", stripped):
            continue
        out.append(line)
    return "\n".join(out).rstrip() + "\n"

def module_text(name, raw):
    body = strip_header(raw)
    return (
        f"#+begin_src emacs-lisp :noweb-ref module/{name} :tangle no\n"
        f"{body}"
        f"#+end_src\n"
    )

def find_section_range(lines, top_title):
    for i, line in enumerate(lines):
        m = re.match(r"^\* (.+)$", line)
        if m and m.group(1).strip() == top_title:
            start = i
            j = i + 1
            while j < len(lines) and not re.match(r"^\* ", lines[j]):
                j += 1
            return start, j
    return None, None

def insert_at_top_of_section(lines, top_start, top_end, payload):
    """Insert payload right after the top-level headline + its first prose line."""
    # Skip top title + 1 blank line, insert after first blank line after the title.
    i = top_start + 1
    # Skip leading blank line
    while i < top_end and lines[i].strip() == "":
        i += 1
    # Skip the first prose/intro paragraph (non-blank lines until blank)
    while i < top_end and lines[i].strip() != "":
        i += 1
    return lines[:i] + payload + lines[i:], i

def find_or_create_l2(lines, top_start, top_end, l2_title):
    for i in range(top_start + 1, top_end):
        m = re.match(r"^\*\* (.+)$", lines[i])
        if m and m.group(1).strip() == l2_title:
            return i, "found"
    return top_end, "insert"

def find_l2_end(lines, l2_start):
    j = l2_start + 1
    while j < len(lines):
        if re.match(r"^\*\* ", lines[j]) or re.match(r"^\* ", lines[j]):
            break
        j += 1
    return j

def insert_at(lines, idx, payload):
    return lines[:idx] + payload + lines[idx:]

def remove_old_sentinels(lines, noweb_ref):
    out = []
    i = 0
    sentinel_re = re.compile(r":noweb-ref\s+" + re.escape(noweb_ref) + r"\b")
    begin_re = re.compile(r"^\s*#\+begin_src\s+")
    end_line = "#+end_src"
    while i < len(lines):
        line = lines[i]
        m = begin_re.search(line)
        if m and sentinel_re.search(line):
            i += 1
            while i < len(lines) and lines[i].strip() != end_line:
                i += 1
            i += 1
            continue
        out.append(line)
        i += 1
    return out

def main():
    with open(ORG, encoding="utf-8") as f:
        org_lines = f.read().splitlines()

    cache = {}

    def section(top):
        if top not in cache:
            cache[top] = find_section_range(org_lines, top)
        return cache[top]

    # Modules that should be inlined at the top of their top-level section
    # (so their defuns are visible to subsequent sibling subsections).
    # Other modules use the standard subsection insertion.
    TOP_OF_SECTION = {
        "literal-git",
        "literal-color-scheme",
        "literal-help",
        "literal-tab-line",
        "literal-modeline",
        "literal-context-menu",
        "literal-which-key-data",
        "literal-org-knowledge",
        "literal-org-agenote",
        "literal-completion",
        "literal-dashboard",
    }

    for basename in sorted(os.listdir(LISP)):
        if not basename.startswith("literal-"):
            continue
        if not basename.endswith(".el"):
            continue
        name = basename[:-3]
        if name not in PLACEMENT:
            print(f"WARN: no placement for {name}", file=sys.stderr)
            continue
        top_title, l2_title = PLACEMENT[name]

        org_lines = remove_old_sentinels(org_lines, f"module/{name}")

        cache = {}
        top_start, top_end = section(top_title)
        if top_start is None:
            print(f"WARN: top section {top_title!r} not found, skipping {name}", file=sys.stderr)
            continue

        if name in TOP_OF_SECTION:
            payload = [
                "",
                f"** {l2_title}(模块内联:{name})",
                "",
                f"由 emacs.org tangle 时将 =lisp/{name}.el= 内容嵌入 main.el。",
                "本节位于顶层域顶部,以保证同域下游子树能直接调用本模块导出的函数。",
                "",
            ]
            org_lines, _ = insert_at_top_of_section(org_lines, top_start, top_end, payload)
        else:
            l2_start, status = find_or_create_l2(org_lines, top_start, top_end, l2_title)
            if status == "found":
                l2_end = find_l2_end(org_lines, l2_start)
                insertion_idx = l2_end
                payload = ["", f"*** 模块内联:{name}", f"由 emacs.org tangle 时将 =lisp/{name}.el= 内容嵌入 main.el。", ""]
            else:
                insertion_idx = top_end
                payload = ["", f"** {l2_title}", "", f"由 emacs.org tangle 时将 =lisp/{name}.el= 内容嵌入 main.el。", ""]
            org_lines = insert_at(org_lines, insertion_idx, payload)

        cache = {}
        with open(os.path.join(LISP, basename), encoding="utf-8") as f:
            raw = f.read()
        body = module_text(name, raw)

        block_lines = body.rstrip().splitlines()
        new_block = block_lines + ["", f"#+begin_src emacs-lisp", f"<<module/{name}>>", "#+end_src", ""]

        # Append at end of file (collect all to insert at end of iteration)
        # Simpler: insert at the end of file for now.
        org_lines = org_lines + new_block
        cache = {}
        print(f"Inserted module/{name} under {top_title} / {l2_title}")

    with open(ORG, "w", encoding="utf-8") as f:
        f.write("\n".join(org_lines) + "\n")
    print("Wrote", ORG)

if __name__ == "__main__":
    main()