# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""ag_lib.dream — memory consolidation（启发式候选发现，只读）。

把 reconcile 拉取的其他 agent memory 中**高频出现、但 KB 尚未记录**的事实，
启发式地提为候选清单，由 agent 读完后用 agenote_add 综合写入 KB。

设计原则（从 MiMoCode `agent/prompt/dream.txt` 提炼，去掉 LLM 依赖）：
1. **Memory is a curated notebook**：KB 是策展过的精华，dream 只发现缺口，
   不复制已有、不自动写卡。**重复的、KB 已覆盖的 → 跳过**。
2. **No extract without evidence**：只在 reconcile 事实里出现 ≥MIN_TERM_FREQ 次
   的主题才升级为候选；没有就明说"无候选"，不凑数。
3. **只读**：返回候选清单（含代表事实正文），**绝不自动写 KB**。
   综合决策由 agent 主导（见 agenote-curator skill 的"Agent 综合步骤"）——
   agent 本身就是 LLM，读 ≤5 条候选后用现有 agenote_add 写卡。
4. **不调 LLM**：纯启发式（关键词频次 + KB 覆盖检查），reconcile 已在写入层
   过滤元消息噪声，dream 复用 is_noise_fact 做二次兜底。

与 MiMoCode dream.txt 的差异：
- MiMoCode 跑 LLM 做 6 阶段提炼；本机把 LLM 角色交给调用 dream 的 agent，
  避免在库内耦合 provider。
- MiMoCode 读 SQLite 轨迹；本机读 reconcile 索引（已是只读摘要）。
- "把重复工作流打包成 skill" 是 distill 的活，不是 dream 的（dream.txt:26）。
"""

import re
from dataclasses import asdict, dataclass, field

from ag_lib.core import is_noise_fact
from ag_lib.reconcile import (
    AGENOTE_ROOT,
    load_reconcile_facts,
)

# ═══════════════════════════════════════════════════════════════════════════════
# 启发式阈值（集中常量，调参只改这里）
# ═══════════════════════════════════════════════════════════════════════════════

MIN_TERM_FREQ = 10  # 关键词在 reconcile 事实中出现 ≥N 次才升级为候选（evidence）
TOP_K_CANDIDATES = 5  # 一次 dream 最多提 K 个候选（避免一次灌爆 KB）
MIN_FACT_LEN = 15  # 太短的事实（<15 字）不提，信息量不足
MIN_TERM_LEN = 3  # 关键词最短长度（过滤"的/了/是"等停用词）


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


# 噪声过滤复用 core 的单一真相源（与 reconcile 写入层一致）。
# dream 这里是二次兜底——reconcile 已在写入层过滤，但 load_reconcile_facts
# 读的是已落盘索引，旧数据可能含未过滤的噪声。
_is_system_content = is_noise_fact


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
        # Skip if representative is system content（二次兜底）
        if _is_system_content(rep):
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
        dry_run: 历史参数，**已无实际效果**——dream 现为纯只读候选发现器，
            不再自动写 KB。保留以兼容 MCP 签名。

    Returns:
        DreamReport。**零候选是合法返回**（message 说明"无待 consolidate 事实"）。
        有候选时 report.candidates 含完整代表事实正文，agent 读取后用
        agenote_add 决定是否综合写入 KB（见 agenote-curator skill 的 Step 3）。
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

    if not candidates:
        report.message = (
            "无候选：reconcile 事实中没有 ≥%d 次出现且 KB 未覆盖的主题（零产物即成功）"
            % MIN_TERM_FREQ
        )
        return report

    report.candidates = [asdict(c) for c in candidates]
    report.message = (
        "发现 %d 个候选（含代表事实正文）。dream 不自动写 KB——agent 综合流程见 "
        "agenote-curator skill 的 'Step 3 — Agent 综合'。" % len(candidates)
    )
    return report
