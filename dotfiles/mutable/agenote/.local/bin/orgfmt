#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# orgfmt — 通用 org-mode 格式化 CLI（独立于 agenote）
#
# 底层格式化核心在 ag_lib.orgfmt（由 agenote Stow 包提供），本脚本通过
# sys.path 加载它。可独立处理任意 .org 文件；--strict 启用 agenote 卡片专用规则。
#
# 用法:
#   orgfmt <file> [file...]            格式化（默认直接写盘）
#   orgfmt --check <file> [file...]    只检查不写盘
#   orgfmt --strict <file> [file...]   启用 agenote 卡片规则（MD→Org、fingerprint）
#   find . -name "*.org" | xargs orgfmt --check   批量检查

import argparse
import os
import sys

# ag_lib.orgfmt 与 agenote 共享部署在 ~/.local/bin/ag_lib/，加入 sys.path
_BIN_DIR = os.path.expanduser("~/.local/bin")
if _BIN_DIR not in sys.path:
    sys.path.insert(0, _BIN_DIR)

from ag_lib.orgfmt import format_file  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="orgfmt",
        description="通用 org-mode 格式化工具（属性对齐、block 大小写、空行、表格、标记间距）",
    )
    parser.add_argument("files", nargs="+", help="目标 .org 文件")
    parser.add_argument(
        "--check",
        action="store_true",
        help="只检查不写盘，打印变更清单",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="启用 agenote 卡片专用规则（Markdown→Org 转换、fingerprint 清理）",
    )
    args = parser.parse_args()

    total_issues = 0
    files_with_issues = 0

    for filepath in args.files:
        if not os.path.isfile(filepath):
            print(f"跳过（非文件）: {filepath}", file=sys.stderr)
            continue
        try:
            changes = format_file(filepath, strict=args.strict, dry_run=args.check)
        except Exception as e:  # noqa: BLE001
            print(f"错误 {filepath}: {e}", file=sys.stderr)
            continue

        if changes:
            total_issues += len(changes)
            files_with_issues += 1
            basename = os.path.basename(filepath)
            print(f"\n{basename} ({len(changes)} 项):")
            for ch in changes:
                print(ch)

    action = "检查" if args.check else "格式化"
    print(
        f"\n{action}完成: {files_with_issues}/{len(args.files)} 个文件"
        f"有变更, 共 {total_issues} 处"
    )

    if args.check and total_issues:
        sys.exit(min(total_issues, 127))


if __name__ == "__main__":
    main()
