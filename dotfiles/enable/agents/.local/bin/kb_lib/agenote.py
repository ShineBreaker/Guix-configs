# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""agenote 子命令分发器。

kb agenote <sub> 的顶层入口。所有子命令复用 kb_lib.cards/memory/lint 的
cmd_* 函数，但绑定 agenote_context()（数据隔离在 KB_ROOT/agenote/）。
search 与 curate 为 agenote 专属增强（跨域加权 / 权重重分配）。
"""

import argparse
import json

from kb_lib.core import (
    agenote_context,
    default_context,
    ensure_dirs,
    die,
    now,
    _init_memory_template_for_ctx,
    _rebuild_index,
    _save_index,
    _query_terms,
    _line_contains_any,
    read_org_title,
    _iter_search_targets,
)
from kb_lib.cards import (
    cmd_add,
    cmd_get,
    cmd_list,
    cmd_fields,
    cmd_tags,
    cmd_inbox,
    cmd_stats,
    cmd_health,
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
from kb_lib.memory import cmd_memory
from kb_lib.lint import cmd_lint


def cmd_agenote_init(args: argparse.Namespace) -> None:
    """初始化 agenote/ 目录结构 + 模板文件。"""
    ctx = agenote_context()
    ctx.experiences.mkdir(parents=True, exist_ok=True)
    ctx.memories.mkdir(parents=True, exist_ok=True)
    ctx.projects.mkdir(parents=True, exist_ok=True)
    if not ctx.inbox.exists():
        ctx.inbox.write_text(
            f"#+title: agenote-inbox\n#+date: [{now()}]\n\n",
            encoding="utf-8",
        )
    if not ctx.memory_org.exists():
        _init_memory_template_for_ctx(ctx)
    if not ctx.index.exists():
        ctx.index.write_text(
            json.dumps(
                {"version": 1, "updated": "", "total": 0, "cards": []},
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    print(f"agenote 已初始化: {ctx.root}")


def agenote_search(args: argparse.Namespace, ctx=None) -> None:
    """跨域加权检索：同时扫人类域 + agenote 域，按 WEIGHT×相关度排序。

    spec §7：人类卡片默认 weight=1.5，agent 卡片 weight=1.0，
    最终分数 = 原始相关度 × WEIGHT。频繁使用的卡片权重更高（curate 时重分配）。
    """
    query = args.query
    human_ctx = default_context()
    agent_ctx = agenote_context()

    terms = _query_terms(query)
    if not terms:
        die("必须提供搜索关键词")
    case_sensitive = getattr(args, "case_sensitive", False)
    normalized_terms = terms if case_sensitive else [t.casefold() for t in terms]
    limit = getattr(args, "limit", 20)

    results = []
    for c in (human_ctx, agent_ctx):
        weight = c.default_weight
        for filepath in _iter_search_targets(c):
            try:
                content = filepath.read_text(encoding="utf-8")
            except OSError:
                continue
            haystack = content if case_sensitive else content.casefold()
            term_hits = [t for t in normalized_terms if t in haystack]
            if not term_hits:
                continue
            occurrence_count = sum(haystack.count(t) for t in term_hits)
            title = read_org_title(content)
            title_hay = title if case_sensitive else title.casefold()
            title_bonus = 25 * sum(1 for t in term_hits if t in title_hay)
            raw_score = len(term_hits) * 100 + occurrence_count + title_bonus
            weighted_score = raw_score * weight  # spec §7 加权公式
            # 提取片段（首个命中行前后 2 行）
            snippet = _make_snippet(content, normalized_terms, case_sensitive)
            results.append(
                {
                    "domain": c.name,
                    "weight": weight,
                    "raw_score": raw_score,
                    "score": round(weighted_score, 1),
                    "title": title,
                    "file": str(filepath),
                    "snippet": snippet,
                }
            )
    results.sort(key=lambda r: r["score"], reverse=True)
    results = results[:limit]

    if getattr(args, "json", False):
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        if not results:
            print(f"未找到匹配: {query}")
            return
        for r in results:
            tag = "[人类]" if r["domain"] == "human" else "[agent]"
            print(f"{tag} {r['title']}  (score={r['score']}, w={r['weight']})")
            if r["snippet"]:
                print(f"    {r['snippet'][:120]}")


def _make_snippet(
    content: str, normalized_terms: list[str], case_sensitive: bool
) -> str:
    """提取首个命中行前后 2 行的片段，最多 200 字符。"""
    lines = content.splitlines()
    hit_indexes = [
        i
        for i, line in enumerate(lines)
        if _line_contains_any(line, normalized_terms, case_sensitive)
    ]
    if not hit_indexes:
        return ""
    start = max(0, hit_indexes[0] - 2)
    end = min(len(lines) - 1, hit_indexes[0] + 2)
    snippet = "\n".join(lines[start : end + 1])
    if len(snippet) > 200:
        snippet = snippet[:200] + "..."
    return snippet


def _bind(subparsers, name: str, cmd_fn, **kwargs):
    """注册一个 agenote 子命令，其 handler 调用 cmd_fn(args, agenote_context())。"""
    p = subparsers.add_parser(name, **kwargs)
    p.set_defaults(_agenote_cmd=cmd_fn)
    return p


def add_agenote_parser(subparsers) -> None:
    """注册 kb agenote 子命令树到主 parser。"""
    ag = subparsers.add_parser(
        "agenote", help="agent 专属记事本（子集，隔离在 agenote/）"
    )
    ag_sub = ag.add_subparsers(dest="agenote_command")

    ag_sub.add_parser("init", help="初始化 agenote/ 目录")

    # ── 卡片轨 ──
    a = _bind(ag_sub, "add", cmd_add, help="添加经验卡片")
    a.add_argument("--title", required=True)
    a.add_argument("--category", default="general")
    a.add_argument("--tech")
    a.add_argument("--type", default="workflow")
    a.add_argument("--owner", default="ai")
    a.add_argument("--entry", help="mistake|note|ascended")
    a.add_argument("--summary")
    a.add_argument("--stdin", action="store_true")

    g = _bind(ag_sub, "get", cmd_get, help="读取卡片（--used 留痕）")
    g.add_argument("target")
    g.add_argument("--used", action="store_true", help="读取后留痕（USAGE_COUNT+1）")

    # list 的完整参数（--category/--type/--owner/--recent/--all）
    lp = _bind(ag_sub, "list", cmd_list, help="列出卡片")
    lp.add_argument("--category")
    lp.add_argument("--type")
    lp.add_argument("--owner")
    lp.add_argument("--recent", type=int)
    lp.add_argument("--all", action="store_true")

    s = ag_sub.add_parser("search", help="跨域加权检索（人类+agent）")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=20)
    s.add_argument("--case-sensitive", action="store_true")
    s.add_argument("--json", action="store_true")
    s.set_defaults(_agenote_cmd=agenote_search)

    _bind(ag_sub, "memory", cmd_memory, help="记忆系统（feedback/project/reference）")
    _bind(ag_sub, "inbox", cmd_inbox, help="快速捕获到 inbox")
    _bind(ag_sub, "stats", cmd_stats, help="统计概览")
    _bind(ag_sub, "health", cmd_health, help="健康度报告")
    _bind(ag_sub, "lint", cmd_lint, help="格式校验")
    _bind(ag_sub, "reindex", None, help="重建索引")  # 特殊处理见 cmd_agenote

    # ── 维护 ──
    t = _bind(ag_sub, "touch", cmd_touch, help="更新时间戳（留痕）")
    t.add_argument("target")
    t.add_argument("--used-only", action="store_true")

    ar = _bind(ag_sub, "archive", cmd_archive, help="归档卡片")
    ar.add_argument("id", nargs="?")
    ar.add_argument("--reason")
    ar.add_argument("--list", dest="list_cards", action="store_true")
    ar.add_argument("--stale", action="store_true")

    rs = _bind(ag_sub, "restore", cmd_restore, help="恢复归档卡片")
    rs.add_argument("id")
    rs.add_argument("--status", default="stable")

    _bind(ag_sub, "deduplicate", cmd_deduplicate, help="检测重复卡片")
    _bind(ag_sub, "review", cmd_review, help="审查卡片")
    _bind(ag_sub, "curate", cmd_curate, help="一键策展（健康+去重+归档+权重重分配）")

    # connect / update 的参数
    cn = _bind(ag_sub, "connect", cmd_connect, help="双向链接两张卡片")
    cn.add_argument("id_a")
    cn.add_argument("id_b")
    cn.add_argument("--desc")

    up = _bind(ag_sub, "update", cmd_update, help="更新卡片")
    up.add_argument("target")
    up.add_argument("--status")
    up.add_argument("--category")
    up.add_argument("--tech")


def cmd_agenote(args: argparse.Namespace) -> None:
    """kb agenote 顶层分发器。"""
    sub = getattr(args, "agenote_command", None)
    if sub is None:
        print("kb agenote — agent 专属记事本")
        print("子命令: init, add, get, list, search, memory, inbox, stats,")
        print("        health, lint, reindex, touch, archive, restore,")
        print("        deduplicate, review, curate, connect, update")
        return

    ctx = agenote_context()
    if sub == "init":
        cmd_agenote_init(args)
        return
    if sub == "reindex":
        ensure_dirs(ctx)
        idx = _rebuild_index(ctx)
        _save_index(idx, ctx)
        print(f"索引已重建: {idx['total']} 条 → {ctx.index}")
        return

    cmd_fn = getattr(args, "_agenote_cmd", None)
    if cmd_fn is None:
        die(f"agenote 子命令 '{sub}' 未绑定")
    cmd_fn(args, ctx)
