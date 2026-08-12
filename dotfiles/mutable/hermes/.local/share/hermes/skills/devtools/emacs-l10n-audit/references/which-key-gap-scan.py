#!/usr/bin/env python3
"""扫描 which-key-zh.el 与 custom/bind 声明之间的缺口。

用法：
  cd ~/.config/emacs
  python3 ~/.local/share/hermes/skills/devtools/emacs-l10n-audit/references/which-key-gap-scan.py

输出：
  1. custom/bind 声明但 which-key-zh.el 未覆盖的键
  2. 文件中存在但描述不一致的键（mismatch）
"""
import re
import sys
from pathlib import Path

def parse_bind_calls(org_content):
    """提取 emacs.org 中所有 custom/bind 和 custom/bind-local 的 (key, desc) 对。"""
    results = []
    for m in re.finditer(r'\(custom/bind\s+"([^"]+)"\s+#\'\S+\s+"([^"]+)"', org_content):
        results.append((m.group(1), m.group(2)))
    for m in re.finditer(r'\(custom/bind-local\s+"([^"]+)"\s+#\'\S+\s+"([^"]+)"', org_content):
        results.append((m.group(1), m.group(2)))
    return results

def parse_wk_tree(lines, prefix, start, end):
    """递归解析 which-key-zh.el 的嵌套树为完整键路径。"""
    result = {}
    i = start
    while i < end:
        stripped = lines[i].strip()
        # Leaf: ("key" . "description")
        m = re.match(r'\("([^"]+)"\s+\.\s+"([^"]+)"\)', stripped)
        if m:
            result[prefix + m.group(1)] = m.group(2)
            i += 1
            continue
        # Sub-section: ("key" "description"
        m = re.match(r'\("([^"]+)"\s+"([^"]+)"\s*$', stripped)
        if m:
            sub_prefix = prefix + m.group(1) + " "
            depth = 1
            j = i + 1
            while j < end and depth > 0:
                depth += lines[j].count('(') - lines[j].count(')')
                j += 1
            result.update(parse_wk_tree(lines, sub_prefix, i + 1, j - 1))
            i = j
            continue
        i += 1
    return result

def main():
    emacs_dir = Path.home() / ".config" / "emacs"
    if not emacs_dir.exists():
        print(f"ERROR: {emacs_dir} not found", file=sys.stderr)
        sys.exit(1)

    org_file = emacs_dir / "emacs.org"
    wk_file = emacs_dir / "data" / "which-key-zh.el"

    bind_calls = parse_bind_calls(org_file.read_text())

    wk_lines = wk_file.read_text().split('\n')
    # Find global section boundaries
    g_start = g_end = None
    in_global = False
    for i, line in enumerate(wk_lines):
        if 'custom:which-key-description-spec' in line:
            in_global = True
        elif in_global and line.strip().startswith("'("):
            g_start = i + 1
            in_global = False
        if 'custom:which-key-major-mode-description-spec' in line:
            g_end = i
            break

    wk_keys = {}
    if g_start and g_end:
        wk_keys = parse_wk_tree(wk_lines, "", g_start, g_end)

    # Cross-reference
    missing = []
    mismatched = []
    for key, desc in bind_calls:
        if key not in wk_keys:
            missing.append((key, desc))
        elif wk_keys[key] != desc:
            mismatched.append((key, desc, wk_keys[key]))

    print(f"custom/bind declarations: {len(bind_calls)}")
    print(f"which-key entries (global): {len(wk_keys)}")
    print(f"Missing: {len(missing)}")
    print(f"Mismatched: {len(mismatched)}")

    if missing:
        print("\n=== MISSING (not in which-key-zh.el) ===")
        for key, desc in missing:
            print(f"  {key}: {desc}")

    if mismatched:
        print("\n=== MISMATCHED ===")
        for key, expected, actual in mismatched:
            print(f"  {key}: expected '{expected}', got '{actual}'")

    # This checks the global section (custom/bind declarations).
    # For major-mode sections (third-party keymap native bindings like
    # org-mode's C-c C-n, C-c C-* etc.), use compare-keymap-dump.py
    # with a keymap dump from scripts/dump-keymaps.el.

if __name__ == '__main__':
    main()
