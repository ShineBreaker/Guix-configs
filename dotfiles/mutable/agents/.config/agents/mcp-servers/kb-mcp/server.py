#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# kb-mcp — 知识库 CLI 的 MCP 瘦壳。
#
# 设计原则:
#   - 薄壳:不重写 kb 业务逻辑,只把 MCP 参数翻译成 subprocess argv。
#   - 单源:kb 是 single source of truth;新增 kb 子命令后,这里加 1 个工具即可。
#   - 简单至上:每个工具 = 1 个装饰器 + 1 个函数体(参照 F014)。
#
# 输出契约:
#   - kb list 默认 JSON;其余子命令纯文本。
#   - 非零退出 → RuntimeError(stderr) → MCP 框架渲染为 isError。
#   - stdin 写入通过 subprocess.run(input=...) 完成,避免 shell heredoc。
#
# 加新工具的模板(只填装饰器 + 函数体即可):
#
#   @mcp.tool()
#   def kb_xxx(arg1: str, opt: int | None = None) -> str:
#       """一句话描述。"""
#       argv = ["xxx", arg1]
#       if opt is not None:
#           argv += ["--opt", str(opt)]
#       return _run_kb(argv)

from __future__ import annotations

import subprocess
from typing import Sequence

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("kb-mcp")

# ─── 调 kb 的唯一入口 ────────────────────────────────────────────────────────


def _run_kb(
    argv: Sequence[str],
    *,
    stdin: str | None = None,
    timeout: float = 30.0,
) -> str:
    """执行 `kb <argv...>` 并返回 stdout。

    非零退出 → RuntimeError(stderr);超时 → subprocess.TimeoutExpired。
    """
    full = ["kb", *argv]
    proc = subprocess.run(
        full,
        input=stdin,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        msg = proc.stderr.strip() or proc.stdout.strip() or f"exit={proc.returncode}"
        raise RuntimeError(f"kb {' '.join(argv)} failed: {msg}")
    return proc.stdout


# ─── 读取组(6 个) ────────────────────────────────────────────────────────────


@mcp.tool()
def kb_search(queries: list[str], context: int = 2, limit: int = 5) -> str:
    """全文检索;多关键词按相关度排序。CLI: `kb search <query> --context N --limit N`

    kb CLI argparse 只接受 1 个 positional `query`, 内部按空格/斜杠/逗号拆多关键词。
    所以这里把 queries list 空格 join 成单个 string。
    """
    argv = [
        "search",
        " ".join(queries),
        "--context",
        str(context),
        "--limit",
        str(limit),
    ]
    return _run_kb(argv, timeout=60.0)


@mcp.tool()
def kb_list_cards(
    category: str | None = None,
    type: str | None = None,  # noqa: A002 — 与 kb CLI flag 一致
    owner: str | None = None,
    all: bool = False,  # noqa: A002 — 与 kb CLI flag 一致
) -> str:
    """列出卡片(默认 JSON)。CLI: `kb list [--category X] [--type Y] [--owner Z] [--all]`"""
    argv = ["list"]
    if category is not None:
        argv += ["--category", category]
    if type is not None:
        argv += ["--type", type]
    if owner is not None:
        argv += ["--owner", owner]
    if all:
        argv.append("--all")
    return _run_kb(argv)


@mcp.tool()
def kb_get_card(id: str) -> str:  # noqa: A002 — 与 kb CLI target 同名
    """读取单张卡片详情。CLI: `kb get <id>`"""
    return _run_kb(["get", id])


@mcp.tool()
def kb_project_memory(project: str = ".") -> str:
    """读取项目记忆(MEMORY.org 节)。CLI: `kb memory --project <name>`"""
    return _run_kb(["memory", "--project", project])


@mcp.tool()
def kb_fields(scope: str | None = None) -> str:
    """列出已有 category/tech/type/owner 值。`scope` 可选 category|tech|type|owner。

    CLI: `kb fields` 或 `kb fields --<scope>`
    """
    argv = ["fields"]
    if scope is not None:
        argv.append(f"--{scope}")
    return _run_kb(argv)


@mcp.tool()
def kb_stats() -> str:
    """知识库统计概览(纯文本)。CLI: `kb stats`"""
    return _run_kb(["stats"])


@mcp.tool()
def kb_tags(tags: list[str]) -> str:
    """按标签检索。CLI: `kb tags <t1> <t2> ...`"""
    return _run_kb(["tags", *tags])


# ─── 写入组(4 个) ────────────────────────────────────────────────────────────


@mcp.tool()
def kb_add_card(
    title: str,
    category: str,
    tech: str,
    type: str,  # noqa: A002 — 与 kb CLI flag 一致
    owner: str,
    summary: str,
    body: str,
    entry: str = "note",
) -> str:
    """添加经验卡片;body 通过 stdin 传给 kb。CLI: `kb add --title ... --stdin <<<body`"""
    argv = [
        "add",
        "--title",
        title,
        "--category",
        category,
        "--tech",
        tech,
        "--type",
        type,
        "--owner",
        owner,
        "--summary",
        summary,
        "--entry",
        entry,
        "--stdin",
    ]
    return _run_kb(argv, stdin=body)


@mcp.tool()
def kb_update_card(
    id: str,  # noqa: A002 — 与 kb CLI target 同名
    status: str | None = None,
    category: str | None = None,
    type: str | None = None,  # noqa: A002 — 与 kb CLI flag 一致
    owner: str | None = None,
    append_to: str | None = None,
    append_text: str | None = None,
    body: str | None = None,
) -> str:
    """更新已有卡片;body 通过 stdin 覆盖正文章节。

    CLI: `kb update <id> [--status S] [--category C] [--type T] [--owner O]
    [--append-to SECTION --append-text TEXT] [--stdin <<<body]`
    """
    argv = ["update", id]
    if status is not None:
        argv += ["--status", status]
    if category is not None:
        argv += ["--category", category]
    if type is not None:
        argv += ["--type", type]
    if owner is not None:
        argv += ["--owner", owner]
    if append_to is not None and append_text is not None:
        argv += ["--append-to", append_to, "--append-text", append_text]
    if body is not None:
        argv.append("--stdin")
    return _run_kb(argv, stdin=body)


@mcp.tool()
def kb_touch_card(id: str, used_only: bool = False) -> str:  # noqa: A002
    """更新卡片时间戳;`used_only=True` 只更新 LAST_USED。

    CLI: `kb touch <id> [--used-only]`
    """
    argv = ["touch", id]
    if used_only:
        argv.append("--used-only")
    return _run_kb(argv)


@mcp.tool()
def kb_connect_cards(id_a: str, id_b: str, desc: str = "") -> str:
    """双向链接两张卡片。CLI: `kb connect <a> <b> --desc X`"""
    argv = ["connect", id_a, id_b]
    if desc:
        argv += ["--desc", desc]
    return _run_kb(argv)


# ─── 快速捕获(1 个) ──────────────────────────────────────────────────────────


@mcp.tool()
def kb_inbox(content: str) -> str:
    """快速捕获想法到 inbox.org。CLI: `kb inbox "<content>"`"""
    return _run_kb(["inbox", content])


# ─── 入口 ─────────────────────────────────────────────────────────────────────


if __name__ == "__main__":
    mcp.run()
