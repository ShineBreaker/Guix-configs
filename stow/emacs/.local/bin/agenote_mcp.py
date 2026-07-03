#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""agenote MCP server — agent 专属记事本的 MCP tool 暴露。

经 pi-mcp-adapter lazy 连接，agent 主循环通过 MCP 协议调用。
复用 ag_lib 数据层函数（返回结构化 dict），不包装 cmd_* 的 stdout。

依赖：python-mcp（Guix home profile 供给，需 7 个包见 config.org 注释）
启动：~/.guix-home/profile/bin/python3 agenote_mcp.py
"""

import contextlib
import io
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime
from pathlib import Path

# 与 kb CLI 相同的 sys.path 注入：支持从源码目录直接运行
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mcp.server.fastmcp import FastMCP  # noqa: E402

from ag_lib.core import (  # noqa: E402
    KB_ROOT,
    HUMAN_DEFAULT_WEIGHT,
    AGENT_DEFAULT_WEIGHT,
    STALE_DAYS,
    STALE_THRESHOLD_DAYS,
    ARCHIVE_THRESHOLD_DAYS,
    VALID_STATUSES,
    KNOWN_AGENTS,
    MEMORY_SECTIONS,
    agenote_context,
    default_context,
    ensure_dirs,
    die,
    now,
    today,
    timestamp_id,
    parse_org_prop,
    read_org_title,
    _card_dict,
    _load_index,
    _save_index,
    _rebuild_index,
    _upsert_card,
    _iter_search_targets,
    _query_terms,
    _line_contains_any,
    _init_memory_template_for_ctx,
    _resolve_card,
    touch_card,
    _parse_float_prop,
    _parse_int_prop,
)
from ag_lib.cards import (  # noqa: E402
    _make_search_snippet,
    cmd_add,
    cmd_list,
    cmd_stats,
    cmd_touch,
    cmd_archive,
    cmd_restore,
    cmd_deduplicate,
    cmd_curate,
)
from ag_lib.health import (  # noqa: E402
    _compute_base_metrics,
    analyze,
    find_gaps,
)
from ag_lib.memory import (  # noqa: E402
    cmd_memory,
    _parse_memory_sections,
    _next_memory_id,
    _find_section_end,
    _memory_overview,
    _memory_add,
    _memory_stale,
    _memory_project,
)

mcp = FastMCP("agenote")

# 预构造两个域上下文（KBContext 是纯数据 dataclass，构造廉价）
_AGENT_CTX = agenote_context()
_HUMAN_CTX = default_context()


# ═══════════════════════════════════════════════════════════════════════════════
# 辅助：捕获 cmd_* 的 stdout + 拦截 die() 的 SystemExit
# ═══════════════════════════════════════════════════════════════════════════════


def _run_cmd_capture(cmd_fn, args, ctx) -> str:
    """调用 cmd_fn(args, ctx)，捕获 stdout 文本。

    ag_lib 的 cmd_* 全部 print 到 stdout 且返回 None。本函数用
    redirect_stdout 捕获输出文本，同时拦截 die() 的 sys.exit(1)。
    """
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            cmd_fn(args, ctx)
    except SystemExit as e:
        # die() 会 sys.exit(1)；让上层 tool handler 把它转成有意义的错误
        raise RuntimeError(f"操作失败: {buf.getvalue().strip() or f'exit({e.code})'}")
    return buf.getvalue().strip()


def _ns(**kwargs) -> "argparse.Namespace":
    """快捷构造 argparse.Namespace（cmd_* 需要 Namespace 入参）。"""
    import argparse

    return argparse.Namespace(**kwargs)


# ═══════════════════════════════════════════════════════════════════════════════
# 跨域加权检索（迁移自 agenote.py，保留 human + agent 双域加权语义）
# ═══════════════════════════════════════════════════════════════════════════════


def _make_snippet_cross(
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


def _cross_domain_search(
    query: str, limit: int = 20, case_sensitive: bool = False
) -> list[dict]:
    """跨域加权检索：同时扫人类域 + agenote 域，按 WEIGHT×相关度排序。

    spec §7：人类卡片默认 weight=1.5，agent 卡片 weight=1.0，
    最终分数 = 原始相关度 × WEIGHT。
    """
    terms = _query_terms(query)
    if not terms:
        raise RuntimeError("必须提供搜索关键词")

    normalized_terms = terms if case_sensitive else [t.casefold() for t in terms]
    results = []

    for c in (_HUMAN_CTX, _AGENT_CTX):
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
            snippet = _make_snippet_cross(content, normalized_terms, case_sensitive)
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

    # ── Phase 2 reconcile 事实：作为额外检索目标（带 source 标记）──────────────
    # 只读拉取的其他 agent memory（hermes 等），weight 低于 KB 卡片，
    # 命中时 domain="reconcile"、source=hermes，便于调用方区分来源。
    try:
        from ag_lib.reconcile import load_reconcile_facts

        for fact in load_reconcile_facts():
            hay = fact.get("content", "")
            haystack = hay if case_sensitive else hay.casefold()
            term_hits = [t for t in normalized_terms if t in haystack]
            if not term_hits:
                continue
            occurrence_count = sum(haystack.count(t) for t in term_hits)
            title = fact.get("title", "")
            title_hay = title if case_sensitive else title.casefold()
            title_bonus = 25 * sum(1 for t in term_hits if t in title_hay)
            raw_score = len(term_hits) * 100 + occurrence_count + title_bonus
            weighted_score = raw_score * fact.get("weight", 0.7)
            results.append(
                {
                    "domain": "reconcile",
                    "source": fact.get("source", ""),
                    "weight": fact.get("weight", 0.7),
                    "raw_score": raw_score,
                    "score": round(weighted_score, 1),
                    "title": title,
                    "file": "",  # reconcile 事实无对应 .org 文件
                    "id": fact.get("id", ""),
                    "snippet": hay[:200] + ("..." if len(hay) > 200 else ""),
                }
            )
    except Exception:
        # reconcile 索引不可用（如首次未跑）→ 静默跳过，不影响 KB 检索
        pass

    results.sort(key=lambda r: r["score"], reverse=True)
    return results[:limit]


# ═══════════════════════════════════════════════════════════════════════════════
# Tool 定义（21 个：读写卡片 / 检索统计 / 记忆 / 策展 / 跨 agent）
# ═══════════════════════════════════════════════════════════════════════════════


@mcp.tool()
def agenote_init() -> dict:
    """初始化 agenote 目录结构 + 模板文件（首次使用时调用）。

    创建 experiences/、memories/、memories/projects/ 目录，
    生成 inbox.org、MEMORY.org、index.json 模板。幂等：已存在的不覆盖。
    """
    ctx = _AGENT_CTX
    ctx.experiences.mkdir(parents=True, exist_ok=True)
    ctx.memories.mkdir(parents=True, exist_ok=True)
    ctx.projects.mkdir(parents=True, exist_ok=True)
    initialized = []
    if not ctx.inbox.exists():
        ctx.inbox.write_text(
            f"#+title: agenote-inbox\n#+date: [{now()}]\n\n",
            encoding="utf-8",
        )
        initialized.append("inbox.org")
    if not ctx.memory_org.exists():
        _init_memory_template_for_ctx(ctx)
        initialized.append("MEMORY.org")
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
        initialized.append("index.json")
    return {
        "root": str(ctx.root),
        "initialized": initialized,
        "message": f"agenote 目录就绪: {ctx.root}",
    }


@mcp.tool()
def agenote_add(
    title: str,
    entry: str = "",
    category: str = "general",
    tech: str = "",
    type: str = "workflow",
    owner: str = "ai",
    summary: str = "",
    body: str = "",
) -> dict:
    """添加一张经验卡片到 agenote。

    Args:
        title: 卡片标题（必填）
        entry: 条目语义 note|mistake|ascended（决定正文模板）
        category: 类别（自由输入，优先复用已有标签）
        tech: 技术栈（默认同 category）
        type: 类型 debug|refactor|research|workflow|feature|config
        owner: 执行者 human|ai|collab
        summary: 一句话总结
        body: 详细内容（对应原 --stdin 的内容）

    Returns:
        包含新卡片 id 和文件路径的 dict
    """
    if not title:
        raise RuntimeError("必须指定 title")

    args = _ns(
        title=title,
        category=category,
        tech=tech,
        type=type,
        owner=owner,
        entry=entry,
        summary=summary,
        stdin=False,
    )
    # cmd_add 通过 sys.stdin.read() 取 body（--stdin 模式）；
    # MCP 场景没有 stdin，改用 append 方式：先创建卡片，再追加 body。
    # 但更简单的做法是：临时把 body 塞进 stdin。
    if body:
        # 模拟 --stdin：用 monkeypatch 临时替换 sys.stdin
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO(body)
            args.stdin = True
            out = _run_cmd_capture(cmd_add, args, _AGENT_CTX)
        finally:
            sys.stdin = old_stdin
    else:
        out = _run_cmd_capture(cmd_add, args, _AGENT_CTX)

    # cmd_add 输出文件路径，解析出 id
    filepath = Path(out.strip()) if out else None
    card_id = ""
    if filepath and filepath.exists():
        content = filepath.read_text(encoding="utf-8")
        card_id = parse_org_prop(content, "ID") or filepath.stem.split("-")[0]
    return {"id": card_id, "file": str(filepath) if filepath else out, "title": title}


@mcp.tool()
def agenote_get(target: str, used: bool = False) -> dict:
    """读取一张卡片的完整内容。

    先用 list/search 找到卡片 ID（如 20260625-014305），再用 ID 调本工具。
    target 接受 ID 或文件名片段。used=True 时读取后递增 USAGE_COUNT（留痕）。

    Args:
        target: 卡片 ID 或文件名片段
        used: 读取后是否留痕（USAGE_COUNT+1）
    """
    ctx = _AGENT_CTX
    p = Path(target)
    # 安全检查：绝对路径必须在 KB_ROOT 内
    if p.is_absolute():
        try:
            p.resolve().relative_to(ctx.root.resolve())
        except ValueError:
            raise RuntimeError(f"路径超出知识库范围: {target}")

    card_path = None
    if p.is_file():
        card_path = p
    else:
        candidates = list(ctx.experiences.rglob(f"*{target}*"))
        candidates = [c for c in candidates if not c.is_symlink() and c.is_file()]
        if candidates:
            card_path = candidates[0]

    if not card_path:
        raise RuntimeError(f"未找到卡片: {target}")

    content = card_path.read_text(encoding="utf-8")
    card_id = parse_org_prop(content, "ID") or card_path.stem.split("-")[0]
    title = read_org_title(content)

    if used:
        touch_card(card_path, "LAST_USED", ctx)

    return {"content": content, "id": card_id, "title": title, "file": str(card_path)}


@mcp.tool()
def agenote_search(
    query: str, limit: int = 20, case_sensitive: bool = False
) -> list[dict]:
    """跨域加权检索：同时扫人类知识库 + agenote 卡片，按权重×相关度排序。

    人类卡片权重 1.5，agent 卡片权重 1.0。返回每条命中的 domain/score/title/snippet。
    这是定位卡片的主要方式——找到 ID 后用 agenote_get 读取全文。

    Args:
        query: 搜索关键词（按空格/斜杠/逗号拆分多关键词）
        limit: 最多返回条数（默认 20）
        case_sensitive: 是否大小写敏感（默认否）
    """
    return _cross_domain_search(query, limit, case_sensitive)


@mcp.tool()
def agenote_list(
    category: str = "",
    type: str = "",
    owner: str = "",
    recent: int = 0,
    all_cards: bool = False,
) -> list[dict]:
    """列出 agenote 卡片，支持按 category/type/owner 过滤。

    Args:
        category: 按类别过滤（精确匹配）
        type: 按类型过滤
        owner: 按执行者过滤
        recent: 只显示最近 N 条（0=不限，需配合 all_cards=False）
        all_cards: 显示全部（忽略 recent）
    """
    ctx = _AGENT_CTX
    limit = 0 if all_cards else (recent or 20)
    index = _load_index(ctx)
    matched = []
    for c in index["cards"]:
        if category and c["category"] != category:
            continue
        if type and c["type"] != type:
            continue
        if owner and c["owner"] != owner:
            continue
        matched.append(
            {
                k: c.get(k, "")
                for k in ("id", "title", "category", "type", "tech", "owner", "created")
            }
        )
        if limit > 0 and len(matched) >= limit:
            break
    return matched


@mcp.tool()
def agenote_stats() -> dict:
    """输出 agenote 统计概览：总卡片数、按类别/类型/执行者/技术栈分布、MEMORY 记忆统计。"""
    ctx = _AGENT_CTX
    ensure_dirs(ctx)
    index = _load_index(ctx)
    cards = index["cards"]

    def _counter(field):
        c = Counter()
        for card in cards:
            c[card.get(field, "unknown")] += 1
        return dict(c.most_common())

    dates = [c["created"] for c in cards if c.get("created")]
    result = {
        "total": len(cards),
        "time_range": [min(dates), max(dates)] if dates else [],
        "by_category": _counter("category"),
        "by_type": _counter("type"),
        "by_owner": _counter("owner"),
        "by_tech": _counter("tech"),
    }

    # MEMORY 统计
    if ctx.memory_org.exists():
        mem_text = ctx.memory_org.read_text(encoding="utf-8")
        result["memory"] = {
            "feedback": len(re.findall(r"^\*\* F\d+", mem_text, re.MULTILINE)),
            "reference": len(re.findall(r"^\*\* R\d+", mem_text, re.MULTILINE)),
        }
        # 陈旧 feedback 计数
        stale = 0
        for m in re.finditer(r":UPDATED:\s*\[(\d{4}-\d{2}-\d{2})\]", mem_text):
            try:
                updated = datetime.strptime(m.group(1), "%Y-%m-%d")
                if (datetime.now() - updated).days > STALE_DAYS:
                    stale += 1
            except ValueError:
                pass
        result["memory"]["stale_feedback"] = stale

    return result


@mcp.tool()
def agenote_health(
    check_duplicates: bool = False,
    check_quality: bool = False,
    stale_days: int = 90,
) -> dict:
    """输出 agenote 健康度报告。

    基础指标（总卡片数、状态分布、孤立率、过时率、类型偏斜、薄弱类别）由
    ag_lib.health._compute_base_metrics 统一计算，与 agenote CLI 的 health 子命令
    共享同一真相源；额外提供 MCP 独有的 by_source（跨 agent 溯源分布）。

    Args:
        check_duplicates: True 时附加疑似重复卡片对（Jaccard，有成本）
        check_quality: True 时附加质量扫描（章节/元数据/Markdown，逐文件有成本）
        stale_days: gaps 报告的陈旧阈值（天，默认 90）

    Returns:
        dict: 基础健康率 + by_source + 分布/矩阵/近期 + 可选 gaps/重复/质量
    """
    ctx = _AGENT_CTX
    ensure_dirs(ctx)

    # 基础健康率（与 agenote health CLI 共享 health.py 真相源）
    base = _compute_base_metrics(ctx)

    # 深度分析：分布 / 矩阵 / 近期 / 可选质量与重复
    deep = analyze(ctx, check_duplicates=check_duplicates, check_quality=check_quality)

    # 空白检测：缺失组合 / 陈旧卡片(时间维) / 纯AI类别
    gaps = find_gaps(ctx, stale_days=stale_days)

    # ── 跨 agent 溯源分布（MCP 独有）─────────────────────────────────────────
    # by_source：每张卡片由哪个 agent 写入。空串 = 人类手写。
    # 来源 KBContext.agent_name → 写卡时落 :SOURCE_AGENT: → _card_dict 解析。
    # 与 reconcile 联动：reconcile 拉取的 hermes/crush 事实打对应 source。
    cards = _load_index(ctx)["cards"]
    source_counts = Counter(c.get("source_agent", "") for c in cards)
    by_source = {
        "counts": dict(sorted(source_counts.items(), key=lambda kv: (-kv[1], kv[0]))),
        "known_agents": sorted(KNOWN_AGENTS),
        "unknown": [s for s in source_counts if s and s not in KNOWN_AGENTS],
    }

    return {
        # 基础健康率（保持原字段兼容）
        "total": base["total"],
        "status": base["status"],
        "by_source": by_source,
        "isolated": base["isolated"],
        "stale": base["stale"],
        "type_skew": base["type_skew"],
        "weak_categories": base["weak_categories"],
        # 深度分析（新增）
        "category_distribution": deep["category_distribution"],
        "type_distribution": deep["type_distribution"],
        "owner_distribution": deep["owner_distribution"],
        "recent_7d": deep["recent_7d"],
        "recent_30d": deep["recent_30d"],
        "category_type_matrix": deep["category_type_matrix"],
        # 空白检测（新增）
        "gaps": {
            "missing_count": gaps["missing_count"],
            "missing_category_type_combos": gaps["missing_category_type_combos"],
            "stale_count": gaps["stale_count"],
            "stale_cards": gaps["stale_cards"],
            "ai_only_categories": gaps["ai_only_categories"],
        },
        # 可选（仅当 check_duplicates/check_quality 时存在）
        **(
            {"potential_duplicates": deep["potential_duplicates"]}
            if check_duplicates
            else {}
        ),
        **(
            {
                "quality_issues": deep["quality_issues"],
                "problem_cards": deep["problem_cards"],
            }
            if check_quality
            else {}
        ),
        **(
            {
                "content_length": {
                    k: deep[k] for k in ("avg_lines", "min_lines", "max_lines")
                }
            }
            if "avg_lines" in deep
            else {}
        ),
    }


@mcp.tool()
def agenote_reconcile(source: str = "all", dry_run: bool = False) -> dict:
    """跨 agent memory 只读 reconcile：把其他 agent 的 memory 拉进检索范围。

    从已注册的 6 个 source（hermes / opencode / crush / codex / claude / pi）
    只读抽取事实，写入 `.reconcile/index.json`，让 agenote_search 能搜到，
    但**绝不写回源文件**、**绝不污染权威 KB**（reconcile 事实 weight 低于 KB 卡片）。

    三重只读保护（每个 extractor 各自实现）：
      1. SQLite: file: URI + mode=ro + PRAGMA query_only=1
      2. JSONL: 仅读，从不构造写语句
      3. 文件不存在 → 返回 ([], [msg]) 不抛异常

    Args:
        source: hermes | opencode | crush | codex | claude | pi | "all"
            （all 跑所有已注册 source；当前 6 个 source）
        dry_run: True 只返回报告不落盘（首次/审核用，默认 False 直接落盘）

    Returns:
        ReconcileReport dict：{source, indexed, skipped, pruned, errors,
        error_details, indexed_items}
    """
    from ag_lib.reconcile import reconcile_source

    report = reconcile_source(source=source, dry_run=dry_run)
    return report.to_dict()


@mcp.tool()
def agenote_extract(
    source: str = "all",
    date: str = "",
    output_dir: str = "",
    dry_run: bool = True,
) -> dict:
    """跨 agent 对话抽取：把 AI 编程工具的原始对话抽取为 Org-mode 文件。

    与 agenote_reconcile 的区别：
      - reconcile：抽取**已沉淀的经验**（agent memory store），写入 .reconcile/index.json
      - extract：抽取**原始对话**（DB/JSONL），输出 Org 文件供人/agent 提炼新经验

    Args:
        source: opencode | crush | codex | claude | pi | hermes | all
        date: 目标日期 YYYY-MM-DD（默认昨天；空字符串 = 不按日期过滤）
        output_dir: 输出目录（默认 ~/Documents/Org/conversations/<date>/）
        dry_run: True 只返回报告不落盘（默认）

    Returns:
        dict: {source, total_facts, output_dir, files: [path, ...], errors: [...]}
    """
    from ag_lib.extract import run_extract

    return run_extract(
        source=source, date=date, output_dir=output_dir, dry_run=dry_run
    )


@mcp.tool()
def agenote_dream(window_days: int = 7, dry_run: bool = True) -> dict:
    """memory consolidation：从 reconcile 事实启发式提炼候选卡片。

    把其他 agent memory 里**高频出现、KB 尚未覆盖**的主题提为候选新卡片。
    **默认 dry_run=True**：只返回候选清单，review 后用 dry_run=False 才写 KB。

    纯启发式（关键词频次），不调 LLM，可安全手动触发。
    **零候选是合法返回**（KB 已覆盖所有高频主题 → 无需 consolidate）。

    Args:
        window_days: 事实时间窗口（保留参数，当前 reconcile 事实无时间戳）
        dry_run: True 只返回候选不写 KB（默认）

    Returns:
        DreamReport dict：{window_days, total_reconcile_facts, candidates,
        promoted, skipped_existing, error_details, message}
    """
    from ag_lib.dream import run_dream

    report = run_dream(window_days=window_days, dry_run=dry_run)
    return report.to_dict()


@mcp.tool()
def agenote_distill(window_days: int = 30, dry_run: bool = True) -> dict:
    """workflow packaging：把重复经验打包成 skill 草稿。

    扫 KB 里**被反复使用的**（type=ascended 或 usage_count≥2）工作流模式，
    按 category+tech 聚类，同主题 ≥2 张才生成 SKILL.md 草稿，写到 `.distill/`
    （**不直接进 skills/ 目录**，人工 review + move 才生效）。

    **零候选是合法返回**（KB 无重复工作流 → 无需 distill）。
    不调 LLM 生成正文（模板填空，正文留空由人工填）。

    Args:
        window_days: 保留参数（当前扫全量 KB）
        dry_run: True 只返回候选不落盘（默认）

    Returns:
        DistillReport dict：{total_kb_cards, candidates, drafted,
        skipped_existing_draft, error_details, message}
    """
    from ag_lib.distill import run_distill

    report = run_distill(window_days=window_days, dry_run=dry_run)
    return report.to_dict()


@mcp.tool()
def agenote_touch(target: str, used_only: bool = False) -> dict:
    """更新卡片时间戳（留痕）。

    每次实际用到一张卡片时调用，递增 USAGE_COUNT。频繁使用的卡片在 curate 时权重提升。

    Args:
        target: 卡片 ID 或文件名片段
        used_only: 只更新 LAST_USED（默认同时更新 LAST_VERIFIED）
    """
    ctx = _AGENT_CTX
    card = _resolve_card(target, ctx)
    if not card:
        raise RuntimeError(f"未找到卡片: {target}")

    if used_only:
        touch_card(card, "LAST_USED", ctx)
        fields = ["LAST_USED"]
    else:
        touch_card(card, "LAST_USED", ctx)
        touch_card(card, "LAST_VERIFIED", ctx)
        fields = ["LAST_USED", "LAST_VERIFIED"]
    return {"updated": fields, "file": card.name}


@mcp.tool()
def agenote_curate() -> dict:
    """一键策展：机械阶段 2 步流水线（无 LLM）。

    Step 1 KB 内策展（健康/权重/去重/归档/索引，详见 ag_lib.cards.cmd_curate）
    Step 2 跨 agent reconcile（全源，清单见 ag_lib.reconcile.KNOWN_SOURCES；
        写入层自动过滤元消息噪声）

    KB 卡片增长由 agent 综合驱动：curate 后调 agenote_dream() 拿候选清单，
    读 representative_content 后用 agenote_add 写新卡片（见 agenote-curator
    skill 的 Step 3）。本 tool 不自动提炼新卡片。

    建议：卡片超过 50 条、或检索质量下降时运行。频率约每周一次。
    """
    ctx = _AGENT_CTX
    # Step 1: KB 内 curate（健康/权重/去重/归档/索引）
    out_kb = _run_cmd_capture(cmd_curate, _ns(threshold=0.7), ctx)

    # Step 2: 跨 agent reconcile（all 源）
    out_recon: dict = {"skipped": True, "note": "step2 disabled"}
    try:
        from ag_lib.reconcile import reconcile_all

        rep = reconcile_all(dry_run=False)
        out_recon = rep.to_dict()
    except Exception as e:
        out_recon = {"skipped": True, "error": str(e)}

    return {
        "kb_curate": out_kb,
        "cross_agent_reconcile": out_recon,
        "curated": True,
    }


@mcp.tool()
def agenote_deduplicate(threshold: float = 0.7) -> list[dict]:
    """检测重复卡片（基于标题相似度 + category/tech 匹配）。

    Args:
        threshold: 相似度阈值 0.0-1.0（默认 0.7）
    """
    ctx = _AGENT_CTX
    index = _load_index(ctx)
    cards_list = [c for c in index["cards"] if c.get("status") != "archived"]

    def _jaccard(s1: str, s2: str) -> float:
        w1 = set(s1.casefold().split())
        w2 = set(s2.casefold().split())
        if not w1 or not w2:
            return 0.0
        return len(w1 & w2) / len(w1 | w2)

    pairs = []
    for i in range(len(cards_list)):
        for j in range(i + 1, len(cards_list)):
            a, b = cards_list[i], cards_list[j]
            sim = _jaccard(a.get("title", ""), b.get("title", ""))
            if a.get("category") == b.get("category"):
                sim += 0.15
            if a.get("tech") and a.get("tech") == b.get("tech"):
                sim += 0.1
            sim = min(sim, 1.0)
            if sim >= threshold:
                pairs.append(
                    {
                        "id_a": a["id"],
                        "id_b": b["id"],
                        "similarity": round(sim, 2),
                        "title_a": a["title"][:60],
                        "title_b": b["title"][:60],
                    }
                )
    pairs.sort(key=lambda x: -x["similarity"])
    return pairs


@mcp.tool()
def agenote_archive(
    target: str = "",
    reason: str = "",
    stale: bool = False,
    list_cards: bool = False,
) -> dict:
    """归档卡片。

    三种模式（互斥）：
    - 归档指定卡片：提供 target（ID 或文件名）
    - 自动归档陈旧：stale=True（归档超过 90 天未验证的 stale 卡片）
    - 列出已归档：list_cards=True

    Args:
        target: 要归档的卡片 ID 或文件名片段
        reason: 归档原因
        stale: 自动归档超过阈值的陈旧卡片
        list_cards: 列出所有已归档卡片
    """
    ctx = _AGENT_CTX
    args = _ns(
        id=target or None,
        reason=reason or None,
        list_cards=list_cards,
        stale=stale,
        json=True,
    )

    if list_cards:
        index = _load_index(ctx)
        archived = [c for c in index["cards"] if c.get("status") == "archived"]
        return {"archived_cards": archived, "count": len(archived)}

    if stale:
        out = _run_cmd_capture(cmd_archive, args, ctx)
        return {"auto_archived": True, "report": out}

    if not target:
        raise RuntimeError("请提供 target（归档指定卡片）或 stale=True（自动归档陈旧）")

    card = _resolve_card(target, ctx)
    if not card:
        raise RuntimeError(f"未找到卡片: {target}")

    _run_cmd_capture(cmd_archive, args, ctx)
    return {"archived": target, "file": card.name}


@mcp.tool()
def agenote_restore(target: str, status: str = "stable") -> dict:
    """恢复一张已归档的卡片。

    Args:
        target: 卡片 ID 或文件名片段
        status: 恢复到的状态（默认 stable）
    """
    ctx = _AGENT_CTX
    args = _ns(id=target, status=status)
    _run_cmd_capture(cmd_restore, args, ctx)
    return {"restored": target, "status": status}


@mcp.tool()
def agenote_reindex() -> dict:
    """全量扫描 experiences/ 重建 index.json。

    当索引与实际卡片不一致时（如手动编辑了 .org 文件）运行。
    """
    ctx = _AGENT_CTX
    ensure_dirs(ctx)
    idx = _rebuild_index(ctx)
    _save_index(idx, ctx)
    return {"total": idx["total"], "index_file": str(ctx.index)}


# ═══════════════════════════════════════════════════════════════════════════════
# 记忆系统（4 个 tool，对应原 kb agenote memory 的多 flag 模式）
# ═══════════════════════════════════════════════════════════════════════════════


@mcp.tool()
def agenote_memory_overview(mem_type: str = "") -> dict:
    """列出 agenote 记忆概览（各节条目数），或按类型过滤列出条目标题。

    Args:
        mem_type: 留空=概览统计；feedback|project|reference=列出该节条目标题
    """
    ctx = _AGENT_CTX
    ensure_dirs(ctx)
    if not ctx.memory_org.exists():
        return {"sections": {}, "note": "记忆文件不存在"}

    text = ctx.memory_org.read_text(encoding="utf-8")
    sections = _parse_memory_sections(text)

    if mem_type:
        # 列出指定节的条目标题
        titles = []
        for sec_name, entries in sections.items():
            if mem_type in sec_name.lower():
                for _s, _e, content in entries:
                    for line in content.split("\n"):
                        m = re.match(r"^\*\*\s+(.+)", line)
                        if m:
                            titles.append(m.group(1))
        return {"type": mem_type, "entries": titles}

    # 概览统计
    result = {}
    for sec_name, entries in sections.items():
        total = sum(len(re.findall(r"^\*\* ", c, re.MULTILINE)) for _, _, c in entries)
        result[sec_name] = total
    return {"sections": result}


@mcp.tool()
def agenote_memory_get(mem_type: str = "") -> dict:
    """读取 agenote MEMORY.org 全文，或指定节的内容。

    Args:
        mem_type: 留空=全文；feedback|project|reference|deprecated=只读该节
    """
    ctx = _AGENT_CTX
    if not ctx.memory_org.exists():
        return {"content": "", "note": "记忆文件不存在"}

    text = ctx.memory_org.read_text(encoding="utf-8")
    if not mem_type:
        return {"content": text}

    sections = _parse_memory_sections(text)
    for sec_name, entries in sections.items():
        if mem_type in sec_name.lower():
            return {"type": mem_type, "content": "\n".join(c for _, _, c in entries)}
    return {"type": mem_type, "content": "", "note": f"未找到 {mem_type} 节"}


@mcp.tool()
def agenote_memory_add(
    title: str,
    mem_type: str = "feedback",
    body: str = "",
    project: str = "",
) -> dict:
    """添加一条记忆到 agenote MEMORY.org。

    feedback=用户对 agent 工作方式的偏好；reference=参考知识；project=项目特定约束。

    Args:
        title: 记忆标题（必填）
        mem_type: feedback|reference|project（默认 feedback）
        body: 详细内容
        project: 项目名（仅 mem_type=project 时需要，记忆存到独立文件）

    Returns:
        包含新记忆 id 的 dict
    """
    ctx = _AGENT_CTX
    ensure_dirs(ctx)

    # 构造 Namespace，body 通过临时 stdin 传入（_memory_add 读 stdin）
    args = _ns(
        type=mem_type,
        title=title,
        stdin=bool(body),
        project=project or None,
        add=True,
        ref=None,
    )
    if body:
        old_stdin = sys.stdin
        try:
            sys.stdin = io.StringIO(body)
            _run_cmd_capture(cmd_memory, args, ctx)
        finally:
            sys.stdin = old_stdin
    else:
        _run_cmd_capture(cmd_memory, args, ctx)

    return {"added": True, "type": mem_type, "title": title, "project": project or None}


@mcp.tool()
def agenote_memory_search(
    project: str = "",
    stale: bool = False,
) -> dict:
    """检索 agenote 记忆。

    两种模式（互斥）：
    - 按项目检索：project=项目名或路径（"."表示当前目录）
    - 列出陈旧记忆：stale=True（超过 30 天未更新）

    Args:
        project: 项目名或路径（留空且 stale=False 时返回 overview）
        stale: 列出陈旧记忆
    """
    ctx = _AGENT_CTX
    if stale:
        args = _ns(stale=True)
        out = _run_cmd_capture(cmd_memory, args, ctx)
        return {"stale_report": out}
    if project:
        args = _ns(project=project)
        # _memory_project 找不到会 sys.exit(1)，捕获转错误
        try:
            out = _run_cmd_capture(cmd_memory, args, ctx)
        except RuntimeError as e:
            return {"project": project, "found": False, "error": str(e)}
        return {"project": project, "found": True, "content": out}
    # 都没提供，返回概览
    args = _ns()
    out = _run_cmd_capture(cmd_memory, args, ctx)
    return {"overview": out}


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    mcp.run()
