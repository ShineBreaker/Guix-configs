#!/usr/bin/env python3
"""比对 keymap dump（来自 dump-keymaps.el）与 which-key-zh.el，找出未翻译条目。

用法:
  # 1. 先从运行中的 Emacs dump keymap（见 scripts/dump-keymaps.el）
  cd ~/.config/emacs
  emacs --batch -Q \
    --eval '(progn (setq user-emacs-directory default-directory) \
                   (load (expand-file-name "init.el")))' \
    -l ~/.local/share/hermes/skills/devtools/emacs-l10n-audit/scripts/dump-keymaps.el \
    > /tmp/keymap-dump.txt

  # 2. 用本脚本比对
  python3 ~/.local/share/hermes/skills/devtools/emacs-l10n-audit/references/compare-keymap-dump.py /tmp/keymap-dump.txt

输出:
  - 已翻译数 / 总数
  - 缺失条目列表（key => command-name）

注意: 本脚本检查 major-mode section（第三方 keymap 原生绑定）。
     custom/bind 声明的覆盖检查用 which-key-gap-scan.py。
"""
import re
import sys
from pathlib import Path


def parse_wk_mode_section(lines, mode_name):
    """解析 which-key-zh.el 中指定 mode 的 section，返回 {full_key: description}。

    同时处理 leaf 和 section-header，后者也会注册为一个条目
    （因为 ("C-e" "导出" ...) 同时声明了 C-c C-e => 导出）。
    """
    result = {}
    in_mode = False
    prefix_stack = []  # [(key, indent)]

    mode_marker = f"({mode_name}"
    for i, line in enumerate(lines):
        stripped = line.strip()

        if mode_marker in stripped and not in_mode:
            in_mode = True
            continue
        if in_mode:
            # 检测下一个 mode 或下一个 setq
            if (stripped.startswith("(") and "-mode" in stripped
                    and mode_name not in stripped):
                break
            if "setq custom:which-key" in stripped and mode_name not in stripped:
                break

        if not in_mode:
            continue

        indent = len(line) - len(line.lstrip())

        # Pop deeper or equal entries from prefix stack
        while prefix_stack and prefix_stack[-1][1] >= indent:
            prefix_stack.pop()

        # Leaf: ("key" . "desc")
        m = re.match(r'\("([^"]+)"\s+\.\s+"([^"]+)"', stripped)
        if m:
            key, desc = m.group(1), m.group(2)
            full_key = " ".join([p[0] for p in prefix_stack] + [key])
            result[full_key] = desc
            continue

        # Section header: ("key" "desc" ...)
        m = re.match(r'\("([^"]+)"\s+"([^"]+)"', stripped)
        if m:
            key, desc = m.group(1), m.group(2)
            full_key = " ".join([p[0] for p in prefix_stack] + [key])
            result[full_key] = desc
            prefix_stack.append((key, indent))

    return result


def parse_dump(dump_text):
    """解析 dump-keymaps.el 的输出，返回 {mode_name: {key: command}}。"""
    modes = {}
    current_mode = None
    for line in dump_text.strip().split("\n"):
        line = line.strip()
        if line.startswith("MODE:"):
            parts = line[5:].split("|", 1)
            current_mode = parts[0]
            if len(parts) > 1 and parts[1] == "NOT_FOUND":
                modes[current_mode] = None
            else:
                modes[current_mode] = {}
        elif current_mode and "|" in line and modes.get(current_mode) is not None:
            key, cmd = line.split("|", 1)
            modes[current_mode][key.strip()] = cmd.strip()
    return modes


def main():
    if len(sys.argv) < 2:
        print("Usage: compare-keymap-dump.py <dump-file>", file=sys.stderr)
        sys.exit(1)

    dump_path = Path(sys.argv[1])
    wk_path = Path.home() / ".config" / "emacs" / "data" / "which-key-zh.el"

    dump_text = dump_path.read_text()
    modes = parse_dump(dump_text)

    wk_lines = wk_path.read_text().split("\n")

    total_missing = 0
    total_covered = 0

    for mode, actual in modes.items():
        if actual is None:
            print(f"\n--- {mode}: KEYMAP NOT FOUND (skip) ---")
            continue

        wk_covered = parse_wk_mode_section(wk_lines, mode)

        missing = []
        for key, cmd in sorted(actual.items()):
            # Skip internal/uninteresting bindings
            if any(s in key for s in ["mouse", "menu-bar", "header-line",
                                       "mode-line", "remap"]):
                continue
            if key in ["ESC TAB", "||", ""]:
                continue
            if key not in wk_covered:
                missing.append((key, cmd))

        covered = len(actual) - len(missing)
        total_covered += covered
        total_missing += len(missing)

        print(f"\n--- {mode}: {covered}/{len(actual)} covered, {len(missing)} missing ---")
        if missing:
            for key, cmd in missing:
                print(f"  {key:30s} => {cmd}")

    print(f"\n=== TOTAL: {total_covered} covered, {total_missing} missing ===")


if __name__ == "__main__":
    main()
