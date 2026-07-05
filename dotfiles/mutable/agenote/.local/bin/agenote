#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# agenote — 人类域知识库 CLI（agenote 体系的人类入口）
# 人机协作经验卡片的增删查改，供人类在终端直接调用。
# agent 域由 agenote_mcp.py（MCP server）暴露，TS 插件由 agenote_cli.py 桥接。
#
# 用法: agenote <子命令> [参数]
#
# 详细子命令列表请运行 agenote help。

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ag_lib.core import (  # noqa: E402
    KB_ROOT,
    KB_EXPERIENCES,
    KB_MEMORIES,
    KB_MEMORY,
    KB_INDEX,
    KB_INBOX,
    VALID_TYPES,
    VALID_OWNERS,
    VALID_ENTRY_TYPES,
    VALID_STATUSES,
    STALE_DAYS,
    die,
    now,
    today,
    _load_index,
    _save_index,
    _rebuild_index,
    ensure_dirs,
    default_context,
    agenote_context,
)
from ag_lib.cards import (  # noqa: E402
    cmd_add,
    cmd_get,
    cmd_list,
    cmd_search,
    cmd_fields,
    cmd_tags,
    cmd_inbox,
    cmd_stats,
    cmd_connect,
    cmd_update,
    cmd_touch,
    cmd_merge,
    cmd_archive,
    cmd_restore,
    cmd_deduplicate,
    cmd_review,
    cmd_curate,
)
from ag_lib.memory import cmd_memory  # noqa: E402
from ag_lib.lint import cmd_lint  # noqa: E402
from ag_lib.health import cmd_health, cmd_gaps  # noqa: E402
from ag_lib.viz.cli import add_viz_parser, cmd_viz  # noqa: E402

# 跨 agent 协同 4 件套（lazy import 到 wrapper 内，避免顶层拉起 sqlite/JSONL 依赖）
from ag_lib.reconcile import reconcile_source  # noqa: E402
from ag_lib.dream import run_dream  # noqa: E402
from ag_lib.distill import run_distill  # noqa: E402
from ag_lib.extract import run_extract  # noqa: E402

# 本 CLI 默认操作 agenote 域（~/Documents/Org/agenote/），与 MCP server 对齐。
# --domain human 切到人类知识库根（~/Documents/Org/）。
# 三入口共享 ag_lib 内核：本 CLI（通用）、agenote_mcp.py（MCP server）、
# agenote_cli.py（TS hooks 桥，已默认 agenote 域）。

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path


def cmd_init(args: argparse.Namespace, ctx=None) -> None:
    """初始化知识库目录结构，可选初始化 git 仓库。"""
    ctx = ctx or default_context()
    root = ctx.root
    # 检查根目录是否已存在且有实质内容
    if root.exists() and any(root.iterdir()):
        has_cards = ctx.experiences.exists() and any(ctx.experiences.iterdir())
        if has_cards:
            print(f"知识库已存在且有内容: {root}")
            print("如需重新初始化，请先备份并删除该目录。")
            return
        # 有目录但无卡片——可能是损坏的初始化，继续
        print(f"知识库目录已存在但为空，继续初始化: {root}")

    # 创建目录和模板文件（复用 ensure_dirs 逻辑）
    ensure_dirs(ctx)
    print(f"目录结构已创建: {root}")

    # git 初始化（默认启用，--no-git 跳过）
    use_git = not args.no_git
    if use_git:
        git_bin = shutil.which("git")
        if not git_bin:
            print("提示: 未找到 git，跳过版本控制初始化。")
            print(
                f"安装 git 后可手动运行: cd {root} && git init && git add -A && git commit -m 'agenote init'"
            )
            return

        git_dir = root / ".git"
        if git_dir.exists():
            print("git 仓库已存在，跳过 git init。")
            return

        # 检查父目录是否已有 git 仓库（避免嵌套）
        parent_git = _find_parent_git(root)
        if parent_git:
            print(f"警告: 父目录已有 git 仓库 ({parent_git})")
            print("跳过 git init 以避免嵌套仓库。")
            print(f"如需独立版本控制，请手动运行: cd {root} && git init")
            return

        # 创建 .gitignore
        gitignore = root / ".gitignore"
        if not gitignore.exists():
            gitignore.write_text("# 机器生成索引\nindex.json\n", encoding="utf-8")

        # git init + 初始 commit
        _run_git(["init"], cwd=root)
        _run_git(["add", ".gitignore", "MEMORY.org", "inbox.org"], cwd=root)
        _run_git(["commit", "-m", "agenote init: 初始化知识库"], cwd=root)
        print("git 仓库已初始化，初始 commit 已创建。")


def cmd_commit(args: argparse.Namespace, ctx=None) -> None:
    """提交知识库变更，封装 git add + commit。"""
    ctx = ctx or default_context()
    root = ctx.root
    git_bin = shutil.which("git")
    if not git_bin:
        die("未找到 git，无法提交。")

    git_dir = root / ".git"
    if not git_dir.exists():
        die(f"知识库未初始化 git 仓库 ({root})。请先运行 'agenote init'。")

    message = args.message
    if not message:
        die("请通过 -m 指定 commit message。")

    # 检查是否有变更
    status = _run_git(["status", "--porcelain"], cwd=root)
    if not status.strip():
        print("没有待提交的变更。")
        return

    # add 所有变更（包括新建、修改、删除）
    _run_git(["add", "-A"], cwd=root)

    # commit
    _run_git(["commit", "-m", message], cwd=root)
    print(f"已提交 ({ctx.name}): {message}")


def _run_git(args: list[str], cwd: Path) -> str:
    """执行 git 命令，返回 stdout。失败时 die。"""
    result = subprocess.run(
        ["git"] + args,
        capture_output=True,
        text=True,
        cwd=str(cwd),
    )
    if result.returncode != 0:
        die(f"git {' '.join(args)} 失败: {result.stderr.strip()}")
    return result.stdout


def _find_parent_git(start: Path) -> Path | None:
    """向上查找父目录中的 .git，返回其路径或 None。"""
    current = start.parent
    while current != current.parent:
        if (current / ".git").exists():
            return current / ".git"
        current = current.parent
    return None


def cmd_reindex(args: argparse.Namespace, ctx=None) -> None:
    """
    全量扫描 experiences/ 目录下所有卡片，重建 index.json。
    """
    ctx = ctx or default_context()
    ensure_dirs(ctx)

    index = _rebuild_index(ctx)
    _save_index(index, ctx)
    print(f"索引已重建 ({ctx.name}): {index['total']} 条卡片 → {ctx.index}")


# ═══════════════════════════════════════════════════════════════════════════════
# 跨 agent 协同 4 件套：reconcile / dream / distill / extract
# 均为薄 wrapper：读 args → 调 ag_lib 函数 → 格式化输出。
# 这 4 个函数内部自建 agenote_context（与 KB 卡片同库），不接受外部 ctx，
# 但为保持 dispatch 签名统一 (args, ctx) 仍接受并忽略 ctx。
# ═══════════════════════════════════════════════════════════════════════════════


def _print_report(d: dict, json_flag: bool, title: str) -> None:
    """统一报告输出：--json 走 JSON，否则人类可读摘要。"""
    if json_flag:
        print(json.dumps(d, ensure_ascii=False, indent=2))
        return
    print(f"=== {title} ===")
    for k, v in d.items():
        if isinstance(v, list):
            print(f"{k}: {len(v)} 项")
            for it in v[:10]:
                if isinstance(it, dict):
                    # 取最像标题/来源的字段
                    label = it.get("title") or it.get("source") or it.get("id") or str(it)[:60]
                    print(f"  + {label}")
                else:
                    print(f"  + {it}")
        elif isinstance(v, dict):
            print(f"{k}:")
            for sk, sv in v.items():
                print(f"  {sk}: {sv}")
        else:
            print(f"{k}: {v}")


def cmd_reconcile(args: argparse.Namespace, ctx=None) -> None:
    """跨 agent memory 只读 reconcile：抽取事实到 .reconcile/index.json。"""
    report = reconcile_source(source=args.source, dry_run=args.dry_run)
    _print_report(report.to_dict(), getattr(args, "json", False),
                  f"reconcile ({args.source}, dry_run={args.dry_run})")


def cmd_dream(args: argparse.Namespace, ctx=None) -> None:
    """从 reconcile 事实启发式提炼候选新卡片。"""
    report = run_dream(window_days=args.window_days, dry_run=args.dry_run)
    _print_report(report.to_dict(), getattr(args, "json", False),
                  f"dream (window={args.window_days}d, dry_run={args.dry_run})")


def cmd_distill(args: argparse.Namespace, ctx=None) -> None:
    """工作流蒸馏：把反复使用的经验打包成 skill 草稿。"""
    report = run_distill(window_days=args.window_days, dry_run=args.dry_run)
    _print_report(report.to_dict(), getattr(args, "json", False),
                  f"distill (window={args.window_days}d, dry_run={args.dry_run})")


def cmd_extract(args: argparse.Namespace, ctx=None) -> None:
    """跨 agent 对话抽取为 Org 文件。"""
    d = run_extract(source=args.source, date=args.date,
                    output_dir=args.output_dir, dry_run=args.dry_run)
    _print_report(d, getattr(args, "json", False),
                  f"extract ({args.source}, dry_run={args.dry_run})")


# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
# 帮助文本
# ═══════════════════════════════════════════════════════════════════════════════


def print_help() -> None:
    print(f"""agenote — 知识库命令行工具

用法: agenote [--domain human|agenote] <子命令> [参数]

全局选项:
  --domain {{human,agenote}}  操作域（默认 agenote，与 MCP server 对齐）
        agenote  → ~/Documents/Org/agenote/（agent 写入的卡片，本 CLI 默认）
        human    → ~/Documents/Org/（人类知识库根）
  --version              显示版本号

子命令:
  add       添加经验卡片
            agenote add --title "标题" [--category 类别] [--tech 技术栈]
                    [--type 类型] [--owner 执行者] [--entry 条目语义]
                    [--summary 总结] [--stdin]

  get       读取卡片详情
            agenote get <卡片文件名或ID>

  list      列出卡片
            agenote list --category 类别 --all
            agenote list [--category 类别] [--type 类型] [--owner 执行者] [--recent N] [--all]

  search    全文检索
            agenote search <关键词...> [--context N] [--limit N]
            agenote search --regex <正则> [--context N]
            默认按空格、/、逗号拆分多关键词，大小写不敏感，按命中词数和次数排序。
            需要旧式 rg/grep 正则行为时显式加 --regex。

  fields    列出已有字段值（用于优先复用标签）
            agenote fields [--category] [--tech] [--type] [--owner]

  tags      按标签检索
            agenote tags <标签> [标签2 ...]

  memory   管理记忆系统
            agenote memory                          列出记忆概览
            agenote memory --type feedback|project|reference  按类型过滤
            agenote memory --project <名称|路径|.>   检索项目记忆
            agenote memory --add --type <类型> --title "标题" --stdin  添加记忆
            agenote memory --stale                   列出陈旧记忆
            agenote memory --touch <ID>              更新时间戳
            agenote memory --archive <ID>            归档记忆到 deprecated
            agenote memory --archive-to-file <ID>    归档 feedback 到 MEMORY-ARCHIVE.org
            agenote memory --stale --auto-archive-days 60  自动归档陈旧 feedback
            agenote memory --project-touch <名称>    更新项目 LAST_ACTIVE
            agenote memory --project <名称> --auto-update  自动更新项目元数据
            agenote memory --get                     查看全文



  reindex   重建知识库索引
            agenote reindex

  lint      格式校验与修复（原 kb-lint）
            agenote lint                 检查所有卡片
            agenote lint --fix           自动修复
            agenote lint --check         仅检查，退出码=问题数
            agenote lint --fix file.org  修复指定文件

  inbox    快速捕获到 inbox.org
            agenote inbox "待捕获的想法" 或 echo "内容" | agenote inbox

  stats    知识库统计概览
            agenote stats

  connect  双向链接两张卡片
            agenote connect <卡片ID> <卡片ID> [--desc 描述]

  update   更新已有卡片
            agenote update <卡片ID> [--status STATUS] [--category 类别] [--tech 技术]
                     [--type 类型] [--owner 执行者] [--append-to 章节 --append-text 内容] [--stdin]

  init     初始化知识库
            agenote init            创建目录结构 + git 仓库 + 初始 commit
            agenote init --no-git   仅创建目录结构，跳过 git

  commit   提交知识库变更
            agenote commit -m "总结"   提交所有变更到 git（.gitignore 排除 index.json）

  touch    更新卡片时间戳
            agenote touch <卡片ID>              更新 LAST_USED + LAST_VERIFIED
            agenote touch <卡片ID> --used-only  只更新 LAST_USED

  merge    合并卡片
            agenote merge <主卡片ID> <次卡片ID>... [--desc 原因]

  archive  归档卡片
            agenote archive <卡片ID> [--reason 原因]  归档指定卡片
            agenote archive --list [--json]           列出归档卡片
            agenote archive --stale                   自动归档过时卡片

  restore  恢复归档卡片
            agenote restore <卡片ID> [--status stable]

  deduplicate 检测重复卡片
            agenote deduplicate [--threshold 0.7] [--json]

  review   审查卡片
            agenote review <卡片ID> [--fix]

  health   知识库健康度报告
            agenote health [--duplicates] [--quality]

  gaps     知识空白检测（类别×类型矩阵）
            agenote gaps [--stale-days 90] [--json]

  curate   一键策展（健康检查+权重重分配+去重+归档陈旧+重建索引）
            agenote curate [--threshold 0.7]
            策展后建议运行: agenote commit -m "策展: <一句话总结>"

  reconcile 跨 agent memory 只读 reconcile（抽取事实到 .reconcile/，不写回源）
            agenote reconcile [--source all] [--dry-run]
            agenote reconcile --source hermes --dry-run

  dream    从 reconcile 事实启发式提炼候选新卡片（不调 LLM，零候选即成功）
            agenote dream [--window-days 7] [--dry-run]

  distill  工作流蒸馏：把反复使用的经验打包成 skill 草稿（写 .distill/，不进 skills/）
            agenote distill [--window-days 30] [--dry-run]

  extract  跨 agent 对话抽取为 Org 文件（输出到 conversations/<date>/）
            agenote extract [--source all] [--date YYYY-MM-DD] [--dry-run]

  help     显示本帮助

配置常量（修改文件头部即可调整）:
  KB_ROOT      人类知识库根 ({KB_ROOT})
  STALE_DAYS   陈旧记忆阈值 ({STALE_DAYS} 天)
  VALID_TYPES  合法 type 值 ({', '.join(sorted(VALID_TYPES))})
  VALID_OWNERS 合法 owner 值 ({', '.join(sorted(VALID_OWNERS))})

默认操作域: agenote（~/Documents/Org/agenote/）
  人类知识库根: {KB_ROOT}
  --domain human 切到人类根；reconcile/dream/distill/extract 始终操作 agenote 域
""")


# ═══════════════════════════════════════════════════════════════════════════════
# 主入口
# ═══════════════════════════════════════════════════════════════════════════════


def main() -> None:
    # 手动拦截 -h/--help（在 argparse 之前，避免 prog 名暴露问题 + 兼容 --domain 前置）
    if "-h" in sys.argv[1:] or "--help" in sys.argv[1:]:
        print_help()
        sys.exit(0)

    parser = argparse.ArgumentParser(
        prog="agenote",
        description="agenote — 知识库命令行工具（默认 agenote 域，与 MCP server 对齐）",
        add_help=False,
    )
    # 全局参数：--domain 决定读写哪棵目录树；--version 修复 argparse 露馅问题
    parser.add_argument(
        "--domain",
        choices=["human", "agenote"],
        default="agenote",
        help="操作域：agenote（默认，~/Documents/Org/agenote/）或 human（~/Documents/Org/）",
    )
    parser.add_argument(
        "--version", action="version", version="agenote 1.0",
    )
    subparsers = parser.add_subparsers(dest="command")

    # ── add ───────────────────────────────────────────────────────────────
    add_parser = subparsers.add_parser("add", help="添加经验卡片")
    add_parser.add_argument("--title", required=True, help="任务标题")
    add_parser.add_argument(
        "--category", default="general", help="类别（自由输入，优先复用已有标签）"
    )
    add_parser.add_argument("--tech", help="技术栈（自由输入，优先复用已有标签）")
    add_parser.add_argument(
        "--type", help="类型（debug|refactor|research|workflow|feature|config）"
    )
    add_parser.add_argument("--owner", default="ai", help="执行者（human|ai|collab）")
    add_parser.add_argument(
        "--entry",
        "--entry-type",
        dest="entry",
        help="条目语义（mistake|note|ascended）",
    )
    add_parser.add_argument("--summary", help="一句话总结")
    add_parser.add_argument(
        "--stdin", action="store_true", help="从标准输入读取详细内容"
    )

    # ── get ───────────────────────────────────────────────────────────────
    get_parser = subparsers.add_parser("get", help="读取卡片详情")
    get_parser.add_argument("target", help="卡片文件名或ID")

    # ── list ──────────────────────────────────────────────────────────────
    list_parser = subparsers.add_parser("list", help="列出卡片")
    list_parser.add_argument("--category", help="按类别过滤")
    list_parser.add_argument("--cagetory", dest="category", help=argparse.SUPPRESS)
    list_parser.add_argument("--type", help="按类型过滤")
    list_parser.add_argument("--owner", help="按执行者过滤")
    list_parser.add_argument("--recent", type=int, help="显示最近 N 条")
    list_parser.add_argument("--all", action="store_true", help="显示全部")
    list_parser.add_argument("--json", action="store_true", help=argparse.SUPPRESS)

    # ── search ────────────────────────────────────────────────────────────
    search_parser = subparsers.add_parser("search", help="全文检索")
    search_parser.add_argument("query", help="关键词；默认按多关键词相关度检索")
    search_parser.add_argument("--context", type=int, default=3, help="上下文行数")
    search_parser.add_argument("--limit", type=int, default=20, help="最多显示的文件数")
    search_parser.add_argument(
        "--max-blocks", type=int, default=4, help="每个文件最多显示的上下文块数"
    )
    search_parser.add_argument(
        "--all-terms", action="store_true", help="只显示包含所有关键词的文件"
    )
    search_parser.add_argument(
        "--case-sensitive", action="store_true", help="大小写敏感匹配"
    )
    search_parser.add_argument(
        "--regex", action="store_true", help="使用旧版 rg/grep 正则检索模式"
    )
    search_parser.add_argument("--json", action="store_true", help="JSON 输出")

    # ── fields ────────────────────────────────────────────────────────────
    fields_parser = subparsers.add_parser("fields", help="列出已有字段值")
    fields_parser.add_argument(
        "--category", action="store_true", help="只列出 category"
    )
    fields_parser.add_argument("--tech", action="store_true", help="只列出 tech")
    fields_parser.add_argument(
        "--type", dest="type_", action="store_true", help="只列出 type"
    )
    fields_parser.add_argument("--owner", action="store_true", help="只列出 owner")
    fields_parser.add_argument("--json", action="store_true", help="JSON 输出")

    # ── tags ──────────────────────────────────────────────────────────────
    tags_parser = subparsers.add_parser("tags", help="按标签检索")
    tags_parser.add_argument("tags", nargs="+", help="标签")
    tags_parser.add_argument("--json", action="store_true", help="JSON 输出")

    # ── memory ──────────────────────────────────────────────────────────
    memory_parser = subparsers.add_parser("memory", help="管理记忆系统")
    memory_parser.add_argument(
        "--type", choices=["feedback", "project", "reference"], help="记忆类型过滤"
    )
    memory_parser.add_argument("--project", metavar="IDENTIFIER", help="项目名或路径")
    memory_parser.add_argument("--add", action="store_true", help="添加记忆")
    memory_parser.add_argument("--get", action="store_true", help="查看记忆全文")
    memory_parser.add_argument("--title", help="记忆标题")
    memory_parser.add_argument(
        "--stdin", action="store_true", help="从标准输入读取内容"
    )
    memory_parser.add_argument("--stale", action="store_true", help="列出陈旧记忆")
    memory_parser.add_argument("--touch", metavar="ID", help="更新记忆时间戳")
    memory_parser.add_argument("--archive", metavar="ID", help="归档记忆到 deprecated")
    memory_parser.add_argument(
        "--archive-to-file", metavar="ID", help="归档 feedback 到 MEMORY-ARCHIVE.org"
    )
    memory_parser.add_argument(
        "--auto-archive-days",
        type=int,
        default=0,
        help="自动归档 >N 天 stale feedback（配合 --stale 使用）",
    )
    memory_parser.add_argument(
        "--project-touch", metavar="NAME", help="更新项目 LAST_ACTIVE 时间戳"
    )
    memory_parser.add_argument(
        "--auto-update",
        action="store_true",
        help="自动更新项目元数据（与 --project 联合使用）",
    )

    # ── reindex ───────────────────────────────────────────────────────────
    subparsers.add_parser("reindex", help="重建知识库索引")

    # ── lint ──────────────────────────────────────────────────────────────
    lint_parser = subparsers.add_parser("lint", help="格式校验与修复（原 kb-lint）")
    lint_parser.add_argument("--fix", action="store_true", help="自动修复")
    lint_parser.add_argument(
        "--check", action="store_true", help="仅检查，退出码=min(问题数,127)"
    )
    lint_parser.add_argument("files", nargs="*", help="目标文件（默认检查全部）")

    # ── inbox ──────────────────────────────────────────────────────────────
    inbox_parser = subparsers.add_parser("inbox", help="快速捕获到 inbox.org")
    inbox_parser.add_argument("content", nargs="?", help="捕获内容")

    # ── stats ───────────────────────────────────────────────────────────────
    subparsers.add_parser("stats", help="知识库统计概览")

    # ── connect ─────────────────────────────────────────────────────────────
    connect_parser = subparsers.add_parser("connect", help="双向链接两张卡片")
    connect_parser.add_argument("id_a", help="卡片 A 的 ID 或文件名")
    connect_parser.add_argument("id_b", help="卡片 B 的 ID 或文件名")
    connect_parser.add_argument("--desc", help="链接描述")

    # ── update ──────────────────────────────────────────────────────────────
    update_parser = subparsers.add_parser("update", help="更新已有卡片")
    update_parser.add_argument("target", help="卡片 ID 或文件名")
    update_parser.add_argument("--status", help="新状态")
    update_parser.add_argument("--category", help="新类别")
    update_parser.add_argument("--tech", help="新技术栈")
    update_parser.add_argument("--type", dest="type_", help="新类型")
    update_parser.add_argument("--owner", help="新执行者")
    update_parser.add_argument("--append-to", help="追加内容到指定章节")
    update_parser.add_argument("--append-text", help="要追加的内容")
    update_parser.add_argument(
        "--stdin", action="store_true", help="从标准输入读取追加内容"
    )

    # ── init ──────────────────────────────────────────────────────────────
    init_parser = subparsers.add_parser("init", help="初始化知识库")
    init_parser.add_argument("--no-git", action="store_true", help="跳过 git 初始化")

    # ── commit ────────────────────────────────────────────────────────────
    commit_parser = subparsers.add_parser("commit", help="提交知识库变更")
    commit_parser.add_argument("-m", "--message", required=True, help="commit message")

    # ── help ──────────────────────────────────────────────────────────────
    subparsers.add_parser("help", help="显示本帮助")

    # ── 新命令 ─────────────────────────────────────────────────────────────

    # ── touch ──────────────────────────────────────────────────────────────
    touch_parser = subparsers.add_parser("touch", help="更新卡片时间戳")
    touch_parser.add_argument("target", help="卡片 ID 或文件名")
    touch_parser.add_argument(
        "--used-only", action="store_true", help="只更新 LAST_USED"
    )

    # ── merge ──────────────────────────────────────────────────────────────
    merge_parser = subparsers.add_parser("merge", help="合并卡片")
    merge_parser.add_argument("primary", help="主卡片 ID")
    merge_parser.add_argument("secondary", nargs="+", help="要合并的卡片 ID")
    merge_parser.add_argument("--desc", help="合并原因")

    # ── archive ─────────────────────────────────────────────────────────────
    archive_parser = subparsers.add_parser("archive", help="归档卡片")
    archive_parser.add_argument("id", nargs="?", help="卡片 ID")
    archive_parser.add_argument("--reason", help="归档原因")
    archive_parser.add_argument(
        "--list", dest="list_cards", action="store_true", help="列出归档卡片"
    )
    archive_parser.add_argument("--stale", action="store_true", help="自动归档过时卡片")
    archive_parser.add_argument("--json", action="store_true", help="JSON 输出")

    # ── restore ─────────────────────────────────────────────────────────────
    restore_parser = subparsers.add_parser("restore", help="恢复归档卡片")
    restore_parser.add_argument("id", help="卡片 ID")
    restore_parser.add_argument(
        "--status", default="stable", help="恢复到的状态（默认 stable）"
    )

    # ── deduplicate ─────────────────────────────────────────────────────────
    dedup_parser = subparsers.add_parser("deduplicate", help="检测重复卡片")
    dedup_parser.add_argument("--threshold", type=float, default=0.7, help="相似度阈值")
    dedup_parser.add_argument("--json", action="store_true", help="JSON 输出")
    dedup_parser.add_argument("--merge", action="store_true", help="自动合并")

    # ── review ──────────────────────────────────────────────────────────────
    review_parser = subparsers.add_parser("review", help="审查卡片")
    review_parser.add_argument("id", help="卡片 ID")
    review_parser.add_argument("--fix", action="store_true", help="自动修复问题")

    # ── health ──────────────────────────────────────────────────────────────
    health_parser = subparsers.add_parser("health", help="知识库健康度报告")
    health_parser.add_argument(
        "--duplicates", action="store_true", help="检测疑似重复卡片"
    )
    health_parser.add_argument(
        "--quality", action="store_true", help="检测质量问题（章节/元数据/Markdown）"
    )

    # ── curate ──────────────────────────────────────────────────────────────
    curate_parser = subparsers.add_parser(
        "curate", help="一键策展（健康+权重+去重+归档陈旧+重建索引）"
    )
    curate_parser.add_argument(
        "--threshold", type=float, default=0.7, help="去重相似度阈值"
    )

    # ── gaps ────────────────────────────────────────────────────────────────
    gaps_parser = subparsers.add_parser("gaps", help="知识空白检测（类别×类型矩阵）")
    gaps_parser.add_argument(
        "--stale-days", type=int, default=90, help="陈旧阈值（天，默认 90）"
    )
    gaps_parser.add_argument("--json", action="store_true", help="JSON 格式输出")

    add_viz_parser(subparsers)

    # ── reconcile ───────────────────────────────────────────────────────────
    reconcile_parser = subparsers.add_parser(
        "reconcile", help="跨 agent memory 只读 reconcile（抽取事实到 .reconcile/）"
    )
    reconcile_parser.add_argument(
        "--source", default="all",
        help="hermes|opencode|crush|codex|claude|pi|zcode|all（默认 all）",
    )
    reconcile_parser.add_argument("--dry-run", action="store_true", help="只预览不落盘")
    reconcile_parser.add_argument("--json", action="store_true", help=argparse.SUPPRESS)

    # ── dream ───────────────────────────────────────────────────────────────
    dream_parser = subparsers.add_parser(
        "dream", help="从 reconcile 事实启发式提炼候选新卡片（不调 LLM）"
    )
    dream_parser.add_argument("--window-days", type=int, default=7, help="回看窗口（天）")
    dream_parser.add_argument("--dry-run", action="store_true", default=True, help="只预览不写 KB")
    dream_parser.add_argument("--json", action="store_true", help=argparse.SUPPRESS)

    # ── distill ─────────────────────────────────────────────────────────────
    distill_parser = subparsers.add_parser(
        "distill", help="工作流蒸馏：把反复使用的经验打包成 skill 草稿"
    )
    distill_parser.add_argument("--window-days", type=int, default=30, help="回看窗口（天）")
    distill_parser.add_argument("--dry-run", action="store_true", default=True, help="只预览不写 .distill/")
    distill_parser.add_argument("--json", action="store_true", help=argparse.SUPPRESS)

    # ── extract ─────────────────────────────────────────────────────────────
    extract_parser = subparsers.add_parser(
        "extract", help="跨 agent 对话抽取为 Org 文件（输出到 conversations/）"
    )
    extract_parser.add_argument(
        "--source", default="all",
        help="opencode|crush|codex|claude|pi|hermes|zcode|all（默认 all）",
    )
    extract_parser.add_argument("--date", default="", help="目标日期 YYYY-MM-DD（默认昨天）")
    extract_parser.add_argument("--output-dir", default="", help="输出目录（默认 conversations/<date>/）")
    extract_parser.add_argument("--dry-run", action="store_true", default=False, help="只预览不落盘（默认会真写盘；传 --dry-run 才不写）")
    extract_parser.add_argument("--json", action="store_true", help=argparse.SUPPRESS)

    args = parser.parse_args()

    if args.command is None or args.command == "help":
        print_help()
        sys.exit(0)

    commands = {
        "add": cmd_add,
        "get": cmd_get,
        "list": cmd_list,
        "search": cmd_search,
        "fields": cmd_fields,
        "tags": cmd_tags,
        "memory": cmd_memory,
        "reindex": cmd_reindex,
        "lint": cmd_lint,
        "inbox": cmd_inbox,
        "stats": cmd_stats,
        "connect": cmd_connect,
        "update": cmd_update,
        "init": cmd_init,
        "commit": cmd_commit,
        # 新命令
        "touch": cmd_touch,
        "merge": cmd_merge,
        "archive": cmd_archive,
        "restore": cmd_restore,
        "deduplicate": cmd_deduplicate,
        "review": cmd_review,
        "health": cmd_health,
        "gaps": cmd_gaps,
        "viz": cmd_viz,
        "curate": cmd_curate,
        # 跨 agent 协同 4 件套
        "reconcile": cmd_reconcile,
        "dream": cmd_dream,
        "distill": cmd_distill,
        "extract": cmd_extract,
    }

    if args.command in commands:
        # 解析 ctx：默认 agenote（与 MCP server 对齐），--domain human 切到人类 KB 根。
        # init 子命令自己管理目录创建（含 ensure_dirs），其余命令按 ctx 确保骨架存在。
        ctx = default_context() if args.domain == "human" else agenote_context()
        if args.command != "init":
            ensure_dirs(ctx)
        commands[args.command](args, ctx)
    else:
        die(f"未知子命令: {args.command}。运行 'agenote help' 查看帮助。")


if __name__ == "__main__":
    main()
