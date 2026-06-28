#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""agenote_cli — hooks 插件用的轻量入口（不走 MCP 协议）。

pi 的 ExtensionAPI 不提供 MCP 调用接口，TS 插件只能 execSync 外部进程。
本脚本复用 kb_lib 内核，输出人类可读文本（hooks 当前就这样解析）。
纯 stdlib，零依赖，直接 python3 运行。

用法:
    agenote_cli health          agenote 健康度报告
    agenote_cli curate          一键策展
    agenote_cli review          对话后审查提示（打印 review 任务模板）

被以下消费者调用:
    - agenote-hooks 插件（/agenote-health、/agenote-curate 命令、状态注入）
    - kb-agent 脚本（direct backend 的 health/curate）
"""

import argparse
import os
import sys

# 与 kb CLI 相同的 sys.path 注入
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from kb_lib.core import agenote_context, ensure_dirs  # noqa: E402
from kb_lib.cards import cmd_health, cmd_curate  # noqa: E402

# kb-agent review 任务的固定模板（原 kb-agent 脚本 REVIEW_TASK 的内容）
REVIEW_TASK = (
    "审查本次对话，检测是否有可记录的经验信号（用户纠正、踩坑、发现更优方案），"
    "并对用到的资料留痕：已有卡片用 agenote touch <id>，联网新知识用 agenote add。"
    "如有经验信号则运行 agenote add 或 agenote memory_add 写入。"
    "（agenote 现已通过 MCP tool 暴露，agent 可直接调用对应 tool）"
)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="agenote_cli",
        description="agenote 轻量 CLI（hooks / kb-agent 入口，不走 MCP）",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health", help="agenote 健康度报告")
    sub.add_parser("curate", help="一键策展（健康+去重+归档+权重重分配）")
    sub.add_parser("review", help="打印 review 任务模板")
    args = parser.parse_args()

    ctx = agenote_context()
    ensure_dirs(ctx)

    # cmd_health / cmd_curate 需要一个 Namespace，但它们只读自身需要的属性。
    # cmd_health 不读 args；cmd_curate 内部会构造子 Namespace 调 cmd_health/cmd_deduplicate。
    ns = argparse.Namespace()

    if args.cmd == "health":
        cmd_health(ns, ctx)
    elif args.cmd == "curate":
        cmd_curate(ns, ctx)
    elif args.cmd == "review":
        print(REVIEW_TASK)


if __name__ == "__main__":
    main()
