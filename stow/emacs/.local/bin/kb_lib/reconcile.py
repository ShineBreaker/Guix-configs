# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""kb_lib.reconcile — 跨 agent memory 只读索引（reconcile）。

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

from kb_lib.core import KB_ROOT, KNOWN_AGENTS

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

    字段对齐 kb_lib _card_dict 的结构，便于 agenote_search 统一处理。
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
KNOWN_SOURCES: dict[str, tuple] = {
    "hermes": (extract_hermes, "hermes holographic memory_store.db (FTS5)"),
    # claude-code / crush / mimocode 源当前不存在（~/.claude/projects 等
    # 实测缺失），暂不登记；待对应 agent memory 落地后再加 extractor。
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

    # KB 优先：跳过与 KB 已有卡片同标题的事实
    kb_titles = _kb_titles()
    kept = [f for f in facts if f.title.casefold() not in kb_titles]
    report.skipped = len(facts) - len(kept)

    # 加载现有 reconcile 索引，剔除该 source 的旧条目（重新填），保留其他 source
    old_index = _load_reconcile_index()
    pruned_old = [f for f in old_index.get("facts", []) if f.get("source") != source]
    report.pruned = sum(
        1 for f in old_index.get("facts", []) if f.get("source") == source
    ) - len(
        [f for f in facts if False]
    )  # placeholder；实际 pruned = 旧-新
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
