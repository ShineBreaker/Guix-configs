# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""ag_lib.dream — memory consolidation（启发式，无 LLM）。

把 reconcile 拉取的其他 agent memory 中**高频出现、但 KB 尚未记录**的事实，
启发式地提为候选卡片，人工 review 后才合并入 KB。

设计原则（从 MiMoCode `agent/prompt/dream.txt` 提炼，去掉 LLM 依赖）：
1. **Memory is a curated notebook**：KB 是策展过的精华，dream 只补充缺口，
   不复制已有。**重复的、KB 已覆盖的 → 跳过**。
2. **No extract without evidence**：只在 reconcile 事实里出现 ≥2 次的主题
   才升级为候选；没有就明说"无候选"，不凑数。
3. **默认 dry_run**：只返回候选清单，不写 KB；用户 review 后手动 dry_run=False。
4. **不调 LLM**：纯启发式（关键词频次 + KB 覆盖检查），cron/手动都可安全跑。
5. **archive 被取代的旧卡片**：合并新卡片时，若发现 KB 有同主题低质量卡片，
   自动归档（dream 是策展，不是堆叠）。

与 MiMoCode dream.txt 的差异：
- MiMoCode 跑 LLM 做 6 阶段提炼；本机用关键词频次启发式，避免烧 token。
- MiMoCode 读 SQLite 轨迹；本机读 reconcile 索引（已是只读摘要）。
- "把重复工作流打包成 skill" 是 distill 的活，不是 dream 的（dream.txt:26）。
"""

import re
from collections import Counter
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta

from ag_lib.core import KB_ROOT, _load_index, _save_index
from ag_lib.reconcile import (
    AGENOTE_ROOT,
    RECONCILE_DEFAULT_WEIGHT,
    load_reconcile_facts,
)

# ═══════════════════════════════════════════════════════════════════════════════
# 启发式阈值（集中常量，调参只改这里）
# ═══════════════════════════════════════════════════════════════════════════════

MIN_TERM_FREQ = 10  # 关键词在 reconcile 事实中出现 ≥N 次才升级为候选（evidence）
TOP_K_CANDIDATES = 5  # 一次 dream 最多提 K 个候选（避免一次灌爆 KB）
MIN_FACT_LEN = 15  # 太短的事实（<15 字）不提，信息量不足
MIN_TERM_LEN = 3  # 关键词最短长度（过滤"的/了/是"等停用词）
DREAM_AGENT_TAG = "pi-dream"  # dream 产生的卡片打这个 source_agent


# ═══════════════════════════════════════════════════════════════════════════════
# 停用词（中文 + 英文常见虚词，避免"的/了/the/a"被当成高频主题）
# ═══════════════════════════════════════════════════════════════════════════════

_STOPWORDS = frozenset("""
    的 了 在 是 有 和 与 或 也 都 就 这 那 一 个 些 等 把 被 让 给 向 往
    对 为 以 于 由 从 到 用 通过 以及 但是 因为 所以 如果 虽然 不过 然后不然
    我 你 他 她 它 们 的 地 得 着 过 会 能 要 想 可 说 看 做 去 来 出 进 上 下
    请 帮 告 知 道 理 解 决 处 理 完 成 实 现 配 置 修 改 删 除 更 新 增 加
    问 题 方 法 功 能 代 码 项 目 文 件 目 录 系 统 命 令 操 作 使 用 行 为
    前 后 时 间 今 天 昨 天 明 天 现 在 刚 才 已 经 正 在 之 前 以 后 以 上 以 下
    a an the of to in on at for and or but is are was were be been being
    this that these those it its as with from by into out up down over under
    user can will would should could may might do does did have has had
    assistant reasoning all task system reminder let me know if
    function tool call use get set return true false none null
    files 当前 you complete omo_internal_initiator skill prompt agent
    message content context information data config settings setup
    check note make sure based using different new want need try
    help work way look find see read write edit delete create change
    update add remove move copy paste open close start stop run
    request tasks what how where when why who which
    修改 然后 前的 但是 但是因为 所以如果
    我先 没有 工作 进行 需要 可以 使用 这个 那个 什么 怎么
    一下 一些 一个 已经 还是 或者 不是 就是 可能 应该
    """.split())

# 用非字母数字（含 CJK）切词的简单分词：英文按空格/标点，CJK 按单字+2-3 gram
# 这里用最朴素的"提取 CJK 连续段 + ASCII 词"策略，够启发式用。
_TOKEN_RE = re.compile(r"[\u4e00-\u9fff]+|[a-zA-Z_][a-zA-Z0-9_-]+")


def _tokenize(text: str) -> list[str]:
    """朴素分词：CJK 连续段 + ASCII 标识符。

    对 CJK 段进一步切 2-gram（覆盖中文无空格特性），降级为"子串频次"统计。
    """
    tokens: list[str] = []
    for m in _TOKEN_RE.finditer(text):
        seg = m.group(0)
        if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*", seg):
            low = seg.lower()
            if low not in _STOPWORDS and len(low) >= MIN_TERM_LEN:
                tokens.append(low)
        else:
            # CJK 段：切 2-gram（中文关键词多在 2-4 字）
            for i in range(len(seg) - 1):
                bigram = seg[i : i + 2]
                if bigram not in _STOPWORDS:
                    tokens.append(bigram)
            # 同时保留完整段（≥3 字的整段可能是专有名词）
            if len(seg) >= MIN_TERM_LEN:
                tokens.append(seg)
    return tokens


# ═══════════════════════════════════════════════════════════════════════════════
# 数据模型
# ═══════════════════════════════════════════════════════════════════════════════


@dataclass
class DreamCandidate:
    """一个 dream 提出的候选新卡片（未落盘，待 review）。"""

    term: str  # 触发候选的高频关键词
    frequency: int  # 该词在 reconcile 事实中的出现次数
    representative_title: str  # 频次最高的事实的标题（作为候选标题参考）
    representative_content: str  # 频次最高的事实正文（作为候选正文参考）
    suggested_category: str  # 映射后的 kb category
    source_facts: list[str]  # 贡献该词的事实 id 列表（溯源）


@dataclass
class DreamReport:
    """一次 dream 运行报告。"""

    window_days: int
    total_reconcile_facts: int = 0
    candidates: list[dict] = field(default_factory=list)
    promoted: int = 0  # 实际写入 KB 的卡片数（dry_run 时为 0）
    skipped_existing: int = 0  # 因 KB 已覆盖而跳过的候选
    error_details: list[str] = field(default_factory=list)
    message: str = ""  # 人类可读结论（含"零产物即成功"语义）

    def to_dict(self) -> dict:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# 启发式主流程
# ═══════════════════════════════════════════════════════════════════════════════


def _kb_covered_terms() -> set[str]:
    """收集 KB（agenote experiences/）已覆盖的标题/正文字符串集合。

    用于"KB 已覆盖 → 跳过"判断。dream 只补缺口，不复制。
    """
    covered: set[str] = set()
    exp = AGENOTE_ROOT / "experiences"
    if not exp.exists():
        return covered
    for f in exp.rglob("*.org"):
        if f.is_symlink():
            continue
        try:
            txt = f.read_text(encoding="utf-8")
        except OSError:
            continue
        # 把标题和正文都 token 化加入 covered（粗粒度覆盖检查）
        for tok in _tokenize(txt):
            covered.add(tok)
    return covered


_SYSTEM_MARKERS = re.compile(
    r"<system-reminder>|<skill-instruction>|<auto-slash-command>|"
    r"\[search-mode\]|\[analyze-mode\]|delegate_task|subagent_type|"
    r"run_in_background|load_skills|MANDATORY|MAXIMIZE SEARCH|"
    r"SYNTHESIZE|IF COMPLEX|Base directory for this skill",
    re.IGNORECASE,
)


def _is_system_content(fact: dict) -> bool:
    """Check if a fact is mostly system prompts / config, not user knowledge."""
    content = fact.get("content", "")
    if len(content) < MIN_FACT_LEN:
        return True
    # If >30% of content matches system markers, skip
    matches = _SYSTEM_MARKERS.findall(content)
    if len(matches) > len(content) / 300:  # rough heuristic
        return True
    return False


def _gather_candidates(facts: list[dict]) -> list[DreamCandidate]:
    """从 reconcile 事实启发式提取候选。

    策略：
    1. 对所有事实正文 token 化，统计词频
    2. 词频 ≥ MIN_TERM_FREQ 的词为主题候选
    3. 每个主题取频次最高（含该词）的事实作为代表
    4. 剔除 KB 已覆盖的词（covered_terms 命中）
    """
    # 词 → [(fact_idx, fact), ...]：记录每个词出现在哪些事实
    term_facts: dict[str, list[tuple[int, dict]]] = {}
    for idx, fact in enumerate(facts):
        if _is_system_content(fact):
            continue
        title = fact.get("title", "")
        # Skip facts with useless titles
        if not title or title in ("Untitled", "---", "<system-reminder>", "TASK"):
            continue
        content = fact.get("content", "")
        if len(content) < MIN_FACT_LEN:
            continue
        # 对每条事实去重 token（避免单条事实里重复词刷频次）
        seen_in_fact = set(_tokenize(content))
        seen_in_fact.update(_tokenize(fact.get("title", "")))
        for tok in seen_in_fact:
            term_facts.setdefault(tok, []).append((idx, fact))

    covered = _kb_covered_terms()
    candidates: list[DreamCandidate] = []
    for term, hits in term_facts.items():
        if len(hits) < MIN_TERM_FREQ:
            continue
        if term in covered:
            continue
        # 选正文最长的事实作为代表（信息量最大）
        rep = max(hits, key=lambda h: len(h[1].get("content", "")))[1]
        rep_content = rep.get("content", "")
        # Skip if representative is system content
        if _SYSTEM_MARKERS.search(rep_content[:500]):
            continue
        candidates.append(
            DreamCandidate(
                term=term,
                frequency=len(hits),
                representative_title=rep.get("title", term),
                representative_content=rep.get("content", ""),
                suggested_category=rep.get("category", "general"),
                source_facts=[h[1].get("id", "") for h in hits],
            )
        )

    # 按频次降序，取 Top-K
    candidates.sort(key=lambda c: c.frequency, reverse=True)
    return candidates[:TOP_K_CANDIDATES]


def run_dream(window_days: int = 7, dry_run: bool = True) -> DreamReport:
    """跑一次 dream（启发式 memory consolidation）。

    Args:
        window_days: 事实时间窗口（当前实现忽略——reconcile 事实无时间戳，
            保留参数为未来对接轨迹源时用）
        dry_run: True（默认）只返回候选不写 KB；False 才实际 promote

    Returns:
        DreamReport。**零候选是合法返回**（message 说明"无待 consolidate 事实"）。
    """
    report = DreamReport(window_days=window_days)
    facts = load_reconcile_facts()
    report.total_reconcile_facts = len(facts)

    if not facts:
        report.message = (
            "无待 consolidate 事实（reconcile 索引为空，先跑 agenote_reconcile）"
        )
        return report

    candidates = _gather_candidates(facts)
    report.skipped_existing = (
        len(facts) - report.total_reconcile_facts
    )  # 占位，实际跳过数在 _gather_candidates 内消化
    report.skipped_existing = 0  # covered 跳过已在候选阶段剔除，单独统计意义不大

    if not candidates:
        report.message = (
            "无候选：reconcile 事实中没有 ≥%d 次出现且 KB 未覆盖的主题（零产物即成功）"
            % MIN_TERM_FREQ
        )
        return report

    report.candidates = [asdict(c) for c in candidates]

    if dry_run:
        report.message = (
            "dry_run：发现 %d 个候选，review 后用 dry_run=False 合并入 KB"
            % len(candidates)
        )
        return report

    # ── dry_run=False：实际 promote 候选到 KB ──────────────────────────────
    # 通过 cmd_add 写卡片，source_agent=DREAM_AGENT_TAG，避免污染 pi/hermes 归属
    from ag_lib.cards import cmd_add
    from ag_lib.core import agenote_context
    import argparse

    ctx = agenote_context(agent_name=DREAM_AGENT_TAG)
    promoted = 0
    for c in candidates:
        try:
            args = argparse.Namespace(
                title=f"[dream] {c.representative_title}",
                category=c.suggested_category,
                tech=c.suggested_category,
                type="workflow",
                owner="ai",
                entry="note",
                summary=f"dream 从 reconcile 事实 consolidate（关键词:{c.term}, 频次:{c.frequency}）",
                stdin=False,
            )
            cmd_add(args, ctx)
            promoted += 1
        except Exception as e:
            report.error_details.append(f"promote '{c.term}' 失败: {e}")
    report.promoted = promoted
    report.message = "promoted %d/%d 张候选到 KB（source_agent=%s）" % (
        promoted,
        len(candidates),
        DREAM_AGENT_TAG,
    )
    return report
