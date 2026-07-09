# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""ag_lib.reconcile — 跨 agent memory 只读索引（reconcile）。

把其他 agent 的 memory **只读拉取**进 agenote 检索范围，让所有 agent 都能
搜到彼此的经验，但**绝不写回源文件**、**绝不污染人类权威 KB**。

设计参考 MiMoCode `memory/reconcile.ts` 的 cc_index 模式（只读 + 类型映射 +
不写回），适配到本机的真实数据源：

当前接入的 source（见 KNOWN_SOURCES）：
- hermes：`~/.local/share/hermes/memory_store.db`（holographic store）
  真实 schema：facts(fact_id, content, category, tags, trust_score, ...)
              + facts_fts(content, tags)  FTS5
  映射：content → 卡片正文（提取【...】括号标题）；category → kb category；
        trust_score → 影响检索 weight。

关键约束（抄 MiMoCode 设计意图）：
1. **只读**：sqlite3 用 `file:...?mode=ro` URI 打开 + `pragma query_only=1`
2. **不破坏隔离**：reconcile 的事实进**单独的** `.reconcile/index.json`，
   不写 `experiences/`；agenote_search 把它作为额外检索目标（带 source 标记）
3. **冲突时 KB 优先**：KB 已有同标题卡片则 source 端跳过（不计入 indexed）
4. **低 weight**：reconcile 卡片默认 weight 低于 KB 卡片，避免淹没权威经验
"""

import json
import re
import sqlite3
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

from ag_lib.core import KB_ROOT, KNOWN_AGENTS, is_noise_fact

# ═══════════════════════════════════════════════════════════════════════════════
# reconcile 索引落盘位置（与 experiences/ 平级，独立目录，绝不混入权威 KB）
# ═══════════════════════════════════════════════════════════════════════════════

AGENOTE_ROOT = KB_ROOT / "agenote"
RECONCILE_DIR = AGENOTE_ROOT / ".reconcile"
RECONCILE_INDEX = RECONCILE_DIR / "index.json"

# reconcile 来源卡片默认权重（低于 KB 卡片 1.0/1.5，避免淹没权威经验）
RECONCILE_DEFAULT_WEIGHT = 0.7


# ═══════════════════════════════════════════════════════════════════════════════
# 数据模型
# ═══════════════════════════════════════════════════════════════════════════════


@dataclass
class ReconciledFact:
    """从外部 agent memory 抽取的一条只读事实（reconcile 索引项）。

    字段对齐 ag_lib _card_dict 的结构，便于 agenote_search 统一处理。
    但 reconcile 卡片**没有对应 .org 文件**（file 字段为空），只活在
    .reconcile/index.json 里，是纯检索辅助。
    """

    id: str  # 跨源唯一：f"{source}:{native_id}"
    source: str  # 来源 agent 名（hermes / crush / claude-code …）
    native_id: str  # 源系统的原始 id（hermes 的 fact_id）
    title: str  # 提取的标题（hermes 的【...】）
    category: str  # 映射后的 kb category
    content: str  # 完整正文
    trust_score: float  # 原始信任度（影响 weight）
    weight: float  # 检索权重（trust 越低 weight 越低）
    tags: list[str] = field(default_factory=list)
    retrieved_at: str = ""  # 本次 reconcile 拉取时间
    timestamp: str = (
        ""  # 对话发生时间（ISO 8601，extractor 能取到就填；空=未知，不过滤）
    )


@dataclass
class ReconcileReport:
    """单次 reconcile 运行报告（对齐 MiMoCode {indexed, pruned} 结构）。"""

    source: str
    indexed: int = 0  # 新增/更新的条目数
    skipped: int = 0  # 因 KB 已有同标题而跳过的条目数
    pruned: int = 0  # 源已删除、本次清理掉的陈旧索引项
    errors: int = 0
    error_details: list[str] = field(default_factory=list)
    indexed_items: list[dict] = field(default_factory=list)  # 前 N 条摘要

    def to_dict(self) -> dict:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# hermes 抽取器（真实 schema）
# ═══════════════════════════════════════════════════════════════════════════════

HERMES_DB = Path.home() / ".local" / "share" / "hermes" / "memory_store.db"

# hermes category → kb category 映射（目前 hermes 只有 general/project/tool）
_HERMES_CATEGORY_MAP = {
    "general": "general",
    "project": "project",
    "tool": "tool",
    "user": "reference",  # 预留：hermes 未来若有 user 类
    "feedback": "feedback",
}

# hermes content 多以【...】开头作为标题，无【】时取首句
_TITLE_BRACKET_RE = re.compile(r"^【([^】]+)】")
_TITLE_SENT_RE = re.compile(r"[^。\n!?:;]+")


def _extract_hermes_title(content: str) -> str:
    """从 hermes fact content 提取简短标题。

    优先【...】括号内容；否则取首句（≤40 字）；兜底截断前 40 字。
    """
    m = _TITLE_BRACKET_RE.match(content.strip())
    if m:
        return m.group(1).strip()[:60]
    first = _TITLE_SENT_RE.match(content.strip())
    raw = (first.group(0).strip() if first else content.strip())[:40]
    return raw or "(hermes fact)"


def _hermes_to_fact(row: sqlite3.Row) -> ReconciledFact:
    """把 hermes facts 一行转成 ReconciledFact。

    row 列：fact_id, content, category, tags, trust_score, retrieval_count,
            helpful_count（hrr_vector 不取，体积大且检索用不到）
    """
    fact_id = row["fact_id"]
    content = row["content"] or ""
    category = _HERMES_CATEGORY_MAP.get(row["category"] or "general", "general")
    trust = float(row["trust_score"] or 0.5)
    # weight：trust 0.5 → 0.7；trust 越高 weight 越高（封顶 1.0，不超过 KB 卡片）
    weight = round(min(1.0, RECONCILE_DEFAULT_WEIGHT + (trust - 0.5)), 2)
    tags_raw = row["tags"] or ""
    tags = [t.strip() for t in re.split(r"[,，]", tags_raw) if t.strip()]
    return ReconciledFact(
        id=f"hermes:{fact_id}",
        source="hermes",
        native_id=str(fact_id),
        title=_extract_hermes_title(content),
        category=category,
        content=content,
        trust_score=trust,
        weight=weight,
        tags=tags,
    )


def _open_hermes_ro(db_path: Path) -> sqlite3.Connection:
    """以只读方式打开 hermes memory_store.db。

    三重只读保护（任一失效都能挡住误写）：
    1. file: URI + mode=ro（SQLite 层面拒绝写）
    2. pragma query_only=1（连接层面拒绝 DML/DDL）
    3. 只 SELECT，从不构造写语句
    """
    if not db_path.exists():
        raise FileNotFoundError(f"hermes memory_store.db 不存在: {db_path}")
    uri = f"file:{db_path}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA query_only = 1")  # 连接级写锁
    return conn


def extract_hermes() -> tuple[list[ReconciledFact], list[str]]:
    """从 hermes memory_store.db 抽取全部 facts（只读）。

    返回 (facts, errors)。errors 是非致命问题（如某行解析失败）。
    """
    facts: list[ReconciledFact] = []
    errors: list[str] = []
    try:
        conn = _open_hermes_ro(HERMES_DB)
    except FileNotFoundError as e:
        # hermes 未运行/未初始化 → 返回空 + 一条说明（不算 fatal error）
        return [], [str(e)]
    try:
        rows = conn.execute(
            "SELECT fact_id, content, category, tags, trust_score, "
            "retrieval_count, helpful_count FROM facts ORDER BY fact_id"
        ).fetchall()
        for row in rows:
            try:
                facts.append(_hermes_to_fact(row))
            except Exception as e:  # 单行解析失败不中断整体
                errors.append(f"fact_id={row['fact_id']}: {e}")
    finally:
        conn.close()
    return facts, errors


# ═══════════════════════════════════════════════════════════════════════════════
# 已注册的 source 表（新增 source 在此登记）
# ═══════════════════════════════════════════════════════════════════════════════

# 每个 source：name → (extractor_fn, 描述)。extractor 返回 (facts, errors)。
# ag_lib.extract.* 5 个抽取器独立模块，三重只读保护由 open_sqlite_ro() 保证。
KNOWN_SOURCES: dict[str, tuple] = {
    "hermes": (extract_hermes, "hermes holographic memory_store.db (FTS5)"),
    "opencode": (
        lambda: __import__(
            "ag_lib.extract.opencode", fromlist=["extract_opencode"]
        ).extract_opencode(),
        "opencode sqlite session/message/part (opencode-stable.db)",
    ),
    "crush": (
        lambda: __import__(
            "ag_lib.extract.crush", fromlist=["extract_crush"]
        ).extract_crush(),
        "crush sqlite (global + project-level DBs)",
    ),
    "codex": (
        lambda: __import__(
            "ag_lib.extract.codex", fromlist=["extract_codex"]
        ).extract_codex(),
        "codex XDG (history.jsonl + sessions/YYYY/MM)",
    ),
    "claude": (
        lambda: __import__(
            "ag_lib.extract.claude", fromlist=["extract_claude"]
        ).extract_claude(),
        "claude XDG (CLAUDE_CONFIG_DIR + XDG_DATA_HOME/claude/transcripts)",
    ),
    "pi": (
        lambda: __import__("ag_lib.extract.pi", fromlist=["extract_pi"]).extract_pi(),
        "pi JSONL 事件流 (parentId 重建)",
    ),
    "zcode": (
        lambda: __import__(
            "ag_lib.extract.zcode", fromlist=["extract_zcode"]
        ).extract_zcode(),
        "zcode sqlite session/message/part (~/.zcode/cli/db/db.sqlite)",
    ),
}


# ═══════════════════════════════════════════════════════════════════════════════
# reconcile 主流程
# ═══════════════════════════════════════════════════════════════════════════════


def _load_reconcile_index() -> dict:
    """加载 .reconcile/index.json，失败返回空骨架。"""
    if RECONCILE_INDEX.exists():
        try:
            return json.loads(RECONCILE_INDEX.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {"version": 1, "updated": "", "by_source": {}, "facts": []}


def _save_reconcile_index(index: dict) -> None:
    """写入 .reconcile/index.json。"""
    RECONCILE_DIR.mkdir(parents=True, exist_ok=True)
    index["updated"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    index["facts"] = sorted(index["facts"], key=lambda f: f["id"])
    by_source: dict[str, int] = {}
    for f in index["facts"]:
        by_source[f["source"]] = by_source.get(f["source"], 0) + 1
    index["by_source"] = dict(sorted(by_source.items(), key=lambda kv: (-kv[1], kv[0])))
    RECONCILE_INDEX.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _kb_titles() -> set[str]:
    """收集 KB（agenote experiences/）已有卡片标题，用于冲突跳过。

    KB 优先原则：reconcile 抽到的事实若与 KB 卡片同名，跳过不索引。
    """
    titles: set[str] = set()
    exp = AGENOTE_ROOT / "experiences"
    if not exp.exists():
        return titles
    for f in exp.rglob("*.org"):
        if f.is_symlink():
            continue
        try:
            txt = f.read_text(encoding="utf-8")
        except OSError:
            continue
        # org 标题行：* DONE <title>
        m = re.search(r"^\* (?:DONE|TODO) (.+)$", txt, re.MULTILINE)
        if m:
            titles.add(m.group(1).strip().casefold())
    return titles


def reconcile_source(source: str = "hermes", dry_run: bool = False) -> ReconcileReport:
    """对单个 source 跑一次只读 reconcile。

    Args:
        source: KNOWN_SOURCES 中的 source 名（或 "all" 跑全部）
        dry_run: True 只返回报告不落盘（首次/审核场景）

    Returns:
        ReconcileReport（含 indexed/skipped/pruned/errors）
    """
    if source == "all":
        return reconcile_all(dry_run=dry_run)
    if source not in KNOWN_SOURCES:
        raise ValueError(f"未知 source: {source}；已注册: {sorted(KNOWN_SOURCES)}")
    if source not in KNOWN_AGENTS:
        # 非 agent 白名单的 source（如 hermes 已在白名单，此处主要是防御）
        pass

    extractor, _desc = KNOWN_SOURCES[source]
    facts, extract_errors = extractor()

    report = ReconcileReport(source=source)
    report.error_details.extend(extract_errors)
    report.errors = len(extract_errors)

    # 0-fact 警告：extractor 跑通但抽不到任何事实（数据未生成 / schema 漂移）
    if not facts and not extract_errors:
        report.error_details.append(
            f"[warn] {source} 抽取到 0 facts（数据未生成或 schema 漂移）"
        )

    # Dedup：跨 DB 重复（如 crush 全局 + 项目级，或 bind-mount 同源）
    # 按 id 去重，保留先出现的（数据库读取顺序由 extractor 决定）
    seen_ids: set[str] = set()
    deduped: list = []
    dup_count = 0
    for f in facts:
        if f.id in seen_ids:
            dup_count += 1
            continue
        seen_ids.add(f.id)
        deduped.append(f)
    facts = deduped
    if dup_count:
        report.error_details.append(f"[info] {source} 去重跳过 {dup_count} 条重复")

    # KB 优先：跳过与 KB 已有卡片同标题的事实
    kb_titles = _kb_titles()
    kept = [f for f in facts if f.title.casefold() not in kb_titles]
    report.skipped = len(facts) - len(kept)

    # 噪声过滤（元消息/工具提示）：extractor 抽取一切，reconcile 是策展层负责过滤
    noise = [f for f in kept if is_noise_fact(asdict(f))]
    kept = [f for f in kept if not is_noise_fact(asdict(f))]
    if noise:
        report.error_details.append(f"[info] {source} 过滤 {len(noise)} 条元消息噪声")

    # 加载现有 reconcile 索引，剔除该 source 的旧条目（重新填），保留其他 source
    old_index = _load_reconcile_index()
    pruned_old = [f for f in old_index.get("facts", []) if f.get("source") != source]
    report.pruned = sum(
        1 for f in old_index.get("facts", []) if f.get("source") == source
    )

    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    new_entries = []
    for f in kept:
        f.retrieved_at = now
        new_entries.append(asdict(f))
    report.indexed = len(new_entries)
    report.indexed_items = [
        {"id": e["id"], "title": e["title"], "category": e["category"]}
        for e in new_entries[:10]  # 报告里只放前 10 条摘要
    ]

    if not dry_run:
        merged = {
            "version": 1,
            "updated": "",
            "by_source": {},
            "facts": pruned_old + new_entries,
        }
        _save_reconcile_index(merged)

    return report


def reconcile_all(dry_run: bool = False) -> ReconcileReport:
    """对所有已注册 source 跑 reconcile，返回合并报告。

    source 字段为 "all"，indexed/skipped/pruned/errors 是各 source 之和，
    indexed_items 是各 source 前 5 条的合并摘要。
    """
    merged = ReconcileReport(source="all")
    for src in KNOWN_SOURCES:
        sub = reconcile_source(src, dry_run=dry_run)
        merged.indexed += sub.indexed
        merged.skipped += sub.skipped
        merged.pruned += sub.pruned
        merged.errors += sub.errors
        merged.error_details.extend(sub.error_details)
        merged.indexed_items.extend(sub.indexed_items[:5])
    return merged


def load_reconcile_facts() -> list[dict]:
    """供 agenote_search 调用：返回当前 reconcile 索引里的全部事实。

    search 层把这些事实作为额外检索目标（带 source=hermes 标记），
    权重用 fact 自带的 weight（低于 KB 卡片）。
    """
    idx = _load_reconcile_index()
    return idx.get("facts", [])


# ── trace 溯源（dream 候选 → 回查原始完整对话）─────────────────
# fact_id 三段式："{source}:{session_id}:{msg_id}"（opencode/zcode/pi/claude 等）
# 或两段式："{source}:{native_id}"（hermes/crush 等）。trace 从中拆出 source +
# session_id，按 source 分发到对应 extractor 的 trace_session（不截断回查原始 DB）。
# 未实现 trace_session 的 source 优雅降级：返回索引层 content（截断摘要）+ 说明。


def trace_fact(fact_id: str) -> dict:
    """从 fact_id 回查原始完整对话（dream trace 溯源入口）。

    fact_id 来自 DreamCandidate.source_trace（= reconcile fact 的 id）。
    解析三段式拆出 source + session_id，按 source 分发：
      - opencode/zcode：trace_session 查 SQLite（完整 message+part，不截断）
      - pi：trace_session 读 .jsonl（完整 parentId 树，不截断）
      - 其余（hermes/crush/codex/claude）：暂未实现 trace_session，降级返回
        索引层 content（截断摘要）+ 降级说明

    返回 dict（含 source/session_id/session 元信息 + messages 列表）。
    出错时返回 {"error": ..., "fact_id": ...}。
    """
    parts = fact_id.split(":", 2)
    if len(parts) < 2:
        return {"error": f"fact_id 格式无法解析: {fact_id}", "fact_id": fact_id}
    source = parts[0]
    session_id = parts[1] if len(parts) >= 2 else ""

    # 已实现 trace_session 的 source 分发
    _TRACE_DISPATCH = {
        "opencode": "ag_lib.extract.opencode",
        "zcode": "ag_lib.extract.zcode",
        "pi": "ag_lib.extract.pi",
    }
    mod_name = _TRACE_DISPATCH.get(source)
    if mod_name:
        try:
            mod = __import__(mod_name, fromlist=["trace_session"])
            result = mod.trace_session(session_id)
            result.setdefault("fact_id", fact_id)
            return result
        except Exception as e:
            return {
                "error": f"trace {source}/{session_id} 失败: {e}",
                "fact_id": fact_id,
            }

    # 未实现 trace_session 的 source：降级返回索引层 content
    idx = _load_reconcile_index()
    for f in idx.get("facts", []):
        if f.get("id") == fact_id:
            return {
                "source": source,
                "fact_id": fact_id,
                "degraded": True,
                "message": (
                    f"{source} 的 trace_session 尚未实现，返回索引层摘要（已截断）。"
                    f"该 content 由 extractor 在建索引时截断，不含完整工具调用/推理。"
                ),
                "content": f.get("content", ""),
                "title": f.get("title", ""),
            }
    return {"error": f"fact_id {fact_id} 在 reconcile 索引中未找到", "fact_id": fact_id}
