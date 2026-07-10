# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""ag_lib.dream — memory consolidation（启发式候选发现，只读 + 溯源）。

把 reconcile 拉取的其他 agent memory 中**高频出现、但 KB 尚未记录**的事实，
启发式地提为候选清单，由 agent 读完后用 agenote_add 综合写入 KB。

设计原则（从 MiMoCode `agent/prompt/dream.txt` 提炼，去掉 LLM 依赖）：
1. **Memory is a curated notebook**：KB 是策展过的精华，dream 只发现缺口，
   不复制已有、不自动写卡。**重复的、KB 已覆盖的 → 跳过**。
2. **No extract without evidence**：只在 reconcile 事实里出现 ≥MIN_TERM_FREQ 次
   的主题才升级为候选；没有就明说"无候选"，不凑数。
3. **只读**：返回候选清单（含代表事实正文 + source_trace 溯源指针），**绝不自动写 KB**。
   综合决策由 agent 主导（见 agenote-curator skill 的"Agent 综合步骤"）——
   agent 本身就是 LLM，读 ≤limit 条候选后用现有 agenote_add 写卡。
4. **不调 LLM，但可溯源**：纯启发式（IDF + 形态学评分 + KB 覆盖检查），reconcile
   已在写入层过滤元消息噪声，dream 复用 is_noise_fact 做二次兜底。索引层 content 是
   截断摘要（opencode/zcode 等 user 截 1000 字、assistant 截 2000 字、tool/patch 丢失），
   故每个候选带 source_trace 指针——agent 用 `agenote trace --id <source_trace>`
   回查原始 DB 的完整对话（含工具调用/推理/补丁），再做综合判断。
5. **分词器：jieba 优先，2-gram 兜底**：jieba（若经 nix profile 自动发现可用）
   对中文产出真实词边界（"配置文件/重新启动"），远胜 2-gram 滑窗；jieba 不可用时
   回退到 2-gram + 胶水字过滤（仍能跑，但产出伪词边界噪声）。

评分（_term_quality_score）：IDF × √df × 形态学权重，TF 作 tie-breaker。
- 旧实现用"频率正态分布（bell_score）"，实测好坏词频率区间几乎完全重叠（都在
  30-140），频率不携带"是否经验词"的信息，导致 todowrite/parallel/我来/明白 这类
  对话噪声冲进 top 候选（见 agenote 卡 20260703-221438 实证：[dream] 卡标题常是
  高频虚词"让我/看看/这是/complete"）。且旧实现的 diversity/rarity 两个因子在真实
  数据上恒为常数（dead code）。
- 主评分：IDF（log(N/df)）让稀有词天然高分，√df 温和补偿高频好词（防止 456 个
  df=MIN_TERM_FREQ 长尾淹没真实高频项目词），形态学权重给代码标识符
  （host-spawn/kb-summarize）强 bonus、CJK 二字虚词（评估/提交）降权。
- TF 信号：旧实现 per-fact 去重成 set 把 TF 全丢了。现在保留 TF（per-fact 内
  min(count,3) 截断），但**不进主评分**——实测让 TF 进 BM25 saturation 反而恶化
  top 候选（df=5 单 fact 内重复的长尾词涌入），因为本项目好词（项目标识符）通常
  每条 fact 只出现 1 次。TF 仅在主评分并列时作 tie-breaker（消除随机排序）。
- 实测 top 候选稳定为高质量项目标识符（guix-configs/self-improving/host-spawn 等），
  对话虚词（removed/complete/让我）已被 IDF + 形态学 + 停用词表三重压制。

与 MiMoCode dream.txt 的差异：
- MiMoCode 跑 LLM 做 6 阶段提炼；本机把 LLM 角色交给调用 dream 的 agent，
  避免在库内耦合 provider。
- MiMoCode 读 SQLite 轨迹；本机读 reconcile 索引（已是只读摘要），并通过 trace 命令
  按需回查原始 DB。
- "把重复工作流打包成 skill" 是 distill 的活，不是 dream 的（dream.txt:26）。
"""

import glob
import hashlib
import math
import os
import re
import sys
import warnings
from collections import Counter
from dataclasses import asdict, dataclass, field
from datetime import datetime, timedelta, timezone

from ag_lib.core import is_noise_fact
from ag_lib.reconcile import (
    AGENOTE_ROOT,
    load_reconcile_facts,
)

# ═══════════════════════════════════════════════════════════════════════════════
# jieba 分词（可选优化；缺失则回退到下方 2-gram 启发式）
# ═══════════════════════════════════════════════════════════════════════════════
# jieba 对中文分词质量远超 2-gram 滑窗（输出"配置文件/重新启动"而非"配置/置文/文件"）。
# 它不在 agenote 的硬依赖里（agenote 跑在 guix python3.12，jieba 装在 nix python3.14
# profile）。这里做自动发现：扫 ~/.nix-profile/lib/python*/site-packages/jieba——
# jieba 是纯 Python 无 C 扩展，py3.12 能直接 import py3.14 路径下的包。
# 找不到或 import 失败则回退到 _GLUE_CHARS + 2-gram 启发式（仍是可用的兜底分词器），
# 并通过 warnings.warn 暴露降级原因（旧实现静默回退，用户不知道分词质量降级了）。

_JIEBA_CACHE: object = False  # 三态：False=未尝试, None=不可用, module=已加载
_JIEBA_LOAD_ERROR: str = ""  # 加载失败原因（用于降级警告）


def _get_jieba():
    """惰性加载 jieba，模块级缓存。

    返回 jieba 模块或 None（不可用时）。缓存结果避免每次 _tokenize 都 glob。
    首次加载失败时通过 warnings.warn 暴露原因（而非静默回退）——让用户知道
    当前走的是 2-gram 兜底分词器，中文分词质量降级了。
    """
    global _JIEBA_CACHE, _JIEBA_LOAD_ERROR
    if _JIEBA_CACHE is not False:
        return _JIEBA_CACHE if _JIEBA_CACHE is not None else None

    here_major = sys.version_info[0], sys.version_info[1]
    # 自动发现：nix profile（python3.14 site-packages）+ 用户 site-packages
    for pattern in (
        "~/.nix-profile/lib/python*/site-packages/jieba/__init__.py",
        "~/.local/lib/python*/site-packages/jieba/__init__.py",
    ):
        for path in glob.glob(os.path.expanduser(pattern)):
            site_dir = os.path.dirname(os.path.dirname(path))  # site-packages/
            if site_dir not in sys.path:
                sys.path.insert(0, site_dir)
            try:
                import jieba  # noqa: SUO005 — 有意动态发现，路径来自上面 glob

                # 版本一致性检查：site-packages 路径里的 pythonX.Y 与当前解释器对比。
                # jieba 纯 Python 当前能跨版本跑，但若路径含 C 扩展或 bytecode cache
                # 版本检查，会静默炸。路径不匹配时记一条 warning（不阻止加载——
                # 实测 jieba 跨 py3.12/py3.14 能正常工作，只是有 SyntaxWarning）。
                m = re.search(r"python(\d+)\.(\d+)", site_dir)
                if m:
                    pkg_major, pkg_minor = int(m.group(1)), int(m.group(2))
                    if (pkg_major, pkg_minor) != here_major:
                        warnings.warn(
                            "jieba 来自 python%d.%d site-packages，当前解释器是 "
                            "python%d.%d。jieba 纯 Python 通常可跨版本运行，但若"
                            "出现 SyntaxWarning 或 ImportError，此处即是原因。"
                            % (pkg_major, pkg_minor, here_major[0], here_major[1]),
                            RuntimeWarning,
                            stacklevel=2,
                        )
                _JIEBA_CACHE = jieba
                return jieba
            except Exception as e:
                # 记录失败原因，继续尝试下一个候选路径（可能有多个 pythonX.Y）
                _JIEBA_LOAD_ERROR = "%s: %r" % (site_dir, e)
                continue
    _JIEBA_CACHE = None  # 标记不可用，后续直接短路
    if not _JIEBA_LOAD_ERROR:
        _JIEBA_LOAD_ERROR = "未找到 jieba 包（~/.nix-profile 和 ~/.local 的 site-packages 都没有）"
    warnings.warn(
        "jieba 不可用，dream 回退到 2-gram 兜底分词器（中文分词质量降级）。"
        "原因: %s" % _JIEBA_LOAD_ERROR,
        RuntimeWarning,
        stacklevel=2,
    )
    return None


# ═══════════════════════════════════════════════════════════════════════════════
# 启发式阈值（集中常量，调参只改这里）
# ═══════════════════════════════════════════════════════════════════════════════

MIN_TERM_FREQ = 5  # 词频下限（低于此直接丢弃，太稀疏不可靠）
DEFAULT_LIMIT = 5  # 一次 dream 默认提 K 个候选（可通过 --limit 覆盖）
DEFAULT_WINDOW_DAYS = 90  # 回看窗口默认值（7d 只剩 5% facts，词频不足；90d 剩 90%）
MIN_FACT_LEN = 15  # 太短的事实（<15 字）不提，信息量不足
MIN_TERM_LEN = 3  # ASCII 关键词最短长度（过滤 is/the/a 等英文虚词）
MIN_CJK_LEN = 2  # CJK 关键词最短长度（中文真实词多为 2 字：相关/对话/避免/浪费）

# 形态学评分权重：经验上"代码标识符"比"CJK 二字虚词"更像具体经验。
# 这些权重乘到 IDF 上（见 _term_quality_score）。
_MORPH_HYPHEN_BONUS = 2.0  # 含 -/_ 的标识符（host-spawn / kb-summarize）强信号
_MORPH_LONGASCII_BONUS = 1.0  # 长全小写串（emacsclient / distrobox）中等信号
_MORPH_CJK2_PENALTY = 0.4  # CJK 二字词（评估/提交/搜索）多为对话虚词，降权

# 时间戳有效年份下限：早于此视为坏数据（epoch ms 误当秒、脏数据），忽略不过滤。
_MIN_VALID_YEAR = 2020


# ═══════════════════════════════════════════════════════════════════════════════
# 停用词（中文 + 英文常见虚词，避免"的/了/the/a"被当成高频主题）
# ═══════════════════════════════════════════════════════════════════════════════
# 设计：停用词表是**兜底防线**，不是主筛。主评分（IDF × √df × 形态学权重）已挡住
# 大部分噪声——此表只清理那些评分仍放到前面的漏网虚词/对话套话。
#
# 注意：CJK 单字（如"问/题/方/法/代/码"）已从表中删除——_tokenize 两条路径都不产
# 单字 token（jieba 路径 MIN_CJK_LEN=2 过滤，2-gram 路径产 2 字），单字停用词是死代码。
# 2-gram 回退路径若产生跨边界伪词，由 _GLUE_CHARS 过滤，不靠此表。

_STOPWORDS = frozenset("""
    的 了 在 是 有 和 与 或 也 都 就 这 那 一 个 些 等 把 被 让 给 向 往
    对 为 以 于 由 从 到 用 通过 以及 但是 因为 所以 如果 虽然 不过
    然后 不然 然后不然
    我 你 他 她 它 们 地 得 着 过 会 能 要 想 可 说 看 做 去 来 出 进 上 下
    请 帮 告 知 道 理 解 决 处 理 完 成 实 现
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
    any they like actual their must about first them then than some such
    very much many most other same another also just only even still well back
    修改 然后 前的 但是 但是因为 所以如果
    我先 没有 工作 进行 需要 可以 使用 这个 那个 什么 怎么
    一下 一些 一个 已经 还是 或者 不是 就是 可能 应该
    完成 帮我 时候 继续 想要 两个 之后 先看 这里 并且 开始 加一 要修
    让我 目前 现在 这是 我们
    了解 你看 需要 进行 可以 下面 里面 上面 同时 所以
    """.split())

# 领域通用词：技术对话中高频出现但不构成具体经验的词。
# 这是**兜底防线**（与 _STOPWORDS 同级）——主评分（IDF × √df × 形态学权重）已挡住
# 大部分噪声，此表只清理评分仍放到前面的漏网虚词。CJK 二字虚词（评估/搜索/调查）
# 虽被形态学降权（×0.4），但仍可能冲进候选，故在此显式列出。
_DOMAIN_GENERIC = frozenset("""
    configuration workspace structure project implementation analysis
    compression compressed custom readme verification success state
    patterns report comprehensive environment specific
    approach process overview summary understanding documentation
    discussion review design system module component feature
    function service interface layer architecture framework pattern
    option setting parameter variable constant type class method
    version release update upgrade migration deployment
    file directory path location source target input output
    error warning message log debug test check verify validate
    fix patch change modify remove add create delete
    request response signal event handler callback listener
    node element attribute property value key pair entry item
    list array map set queue stack tree graph network
    base root head tail top bottom left right inner outer
    simple basic standard default special general common
    exploring looking asking looks topic specifically current
    there exactly whether particular basically actually definitely
    seems appears might maybe perhaps probably likely
    understand removed messages projects documents packages configs
    brokenshine
    布局 窗口 探索 经验 能够 我会 操作 选项 界面 面板
    功能 模块 组件 接口 架构 框架 模式 版本 发布 迁移
    目录 路径 位置 源 目标 输入 输出
    错误 警告 消息 日志 调试 测试 检查 验证 修复 补丁
    请求 响应 信号 事件 回调 监听器 节点 元素 属性
    列表 数组 映射 集合 队列 栈 网络 基础 根
    头 尾 顶部 底部 左侧 右侧 内部 外部 本地 远程
    简单 基本 标准 默认 特殊 通用 常见 具体 特别
    有没有 找到 需求 问题 方面 情况 状态 内容 结果
    评估 提交 搜索 调查 侦察 现有 按照 根据 这样 等等
    非常 一份 明白 我来 知识库
   """.split())

# CJK 功能字（仅在 jieba 不可用、走 2-gram 回退路径时使用）：
# 这些字几乎从不出现在真实词的内部，只作为词间"胶水"。2-gram 滑动窗跨词边界
# 产生 我需/是一/的时/中的 这类伪词——它们总含一个胶水字。据此过滤：
# 2-gram 任一字符是胶水字即丢弃（无需词典即可消除跨边界噪声）。
# 经实测在干净 reconcile 数据上：跨边界伪词 100% 含胶水字，
# 真词（配置/修复/检测/并行）无一含胶水字。
# jieba 路径不需要这个（jieba.cut 直接产出真实词边界）。
_GLUE_CHARS = frozenset(
    "的了吗呢吧啊哦呀哇么我你他她它是在有和无或但也还就更都只又再已"
    "将把被让给向往对为以于由从到用着过"
)


def _term_quality_score(term: str, df: int, total_facts: int) -> float:
    """综合评分 = IDF × √df × 形态学权重（主评分）。

    **本函数是主评分，不包含 TF**。TF 信号在 _gather_candidates 里保留并作 score
    并列时的 tie-breaker（不进主评分——实测让 TF 进 BM25 saturation 会恶化候选，
    见模块 docstring）。

    IDF（inverse document frequency）：log(total_facts / df)。稀有词天然高分，
    替代旧 bell_score 的"频率正态分布"假设（实测好坏词频率区间几乎完全重叠，
    频率不携带"是否经验词"的信息）。

    √df（频率平方根补偿）：纯 IDF 会把所有最低频词（df=MIN_TERM_FREQ）排到最前，
    但大量 df=5 的词是一次性长尾（token 哈希/无关项目名），淹没真正高频的好词。
    √df 温和补偿高频词，让高频项目标识符能进 top，又不像纯 df（TF-IDF）那样让
    高频坏词独占榜首。

    形态学权重：代码标识符（含 -/_）是"具体工具/概念"的强信号，CJK 二字词
    多为对话虚词（评估/提交/搜索），据此加减权。
    """
    idf = math.log(total_facts / df) if df > 0 and total_facts > 0 else 0.0
    freq_boost = math.sqrt(df)
    weight = 1.0
    if (
        "-" in term or "_" in term
    ):  # 代码标识符：host-spawn / kb-summarize / self-improving
        weight += _MORPH_HYPHEN_BONUS
    elif re.fullmatch(
        r"[a-z][a-z0-9]{6,}", term
    ):  # 长全小写：emacsclient / distrobox / subagent
        weight += _MORPH_LONGASCII_BONUS
    if re.fullmatch(r"[\u4e00-\u9fff]{2}", term):  # CJK 二字词多为虚词：评估/提交/搜索
        weight *= _MORPH_CJK2_PENALTY
    return idf * freq_boost * weight


def _parse_timestamp(ts: str):
    """解析 reconcile fact 的 timestamp 字段，返回 aware datetime 或 None。

    容忍 3 种格式（各 source 不统一，见 reconcile 探查）：
    - epoch ms（全数字，长度 13）：opencode/zcode/crush
    - ISO 8601（含 Z 或时区偏移）：pi/claude/codex
    - 空串：hermes（无时间戳，调用方负责"无 ts 默认保留"语义）

    坏数据容错：解析成功但年份 < _MIN_VALID_YEAR 视为无效（如 epoch ms 被误当
    秒解析出的 1970 日期），返回 None——这类 fact 不参与时间过滤，按"无 ts"
    处理（默认保留）。
    """
    if not ts:
        return None
    ts = ts.strip()
    if not ts:
        return None
    # epoch ms（全数字）
    if ts.isdigit():
        try:
            dt = datetime.fromtimestamp(int(ts) / 1000, tz=timezone.utc)
        except (ValueError, OverflowError, OSError):
            return None
        return dt if dt.year >= _MIN_VALID_YEAR else None
    # ISO 8601
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt if dt.year >= _MIN_VALID_YEAR else None


# 切 CJK 连续段 + ASCII 标识符，再交给 _tokenize 做子路径分词。
_TOKEN_RE = re.compile(r"[\u4e00-\u9fff]+|[a-zA-Z_][a-zA-Z0-9_-]+")


def _tokenize(text: str) -> list[str]:
    """分词：jieba 优先（若可用），否则回退到 2-gram 启发式。

    jieba 路径：对 CJK 段用 jieba.cut 得到真实词（"配置文件/重新启动"），
    单字功能词（"的/了/是"）经 _STOPWORDS + _DOMAIN_GENERIC + MIN_CJK_LEN 过滤。
    回退路径：CJK 段切 2-gram + 胶水字过滤（仍能跑，但产出伪词边界噪声）。

    ASCII 标识符两条路径一致（小写化 + 停用词 + 领域通用词 + MIN_TERM_LEN 长度过滤）。
    """
    jieba = _get_jieba()
    tokens: list[str] = []
    for m in _TOKEN_RE.finditer(text):
        seg = m.group(0)
        if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_-]*", seg):
            low = seg.lower()
            if (
                low not in _STOPWORDS
                and low not in _DOMAIN_GENERIC
                and len(low) >= MIN_TERM_LEN
            ):
                tokens.append(low)
            continue
        # CJK 段
        if jieba is not None:
            # jieba.cut 输出真实词（"配置文件/重新启动"），单字功能词靠
            # MIN_CJK_LEN + _STOPWORDS 过滤；中文真实词多为 2 字，故阈值低于 ASCII。
            for word in jieba.cut(seg):
                if (
                    len(word) >= MIN_CJK_LEN
                    and word not in _STOPWORDS
                    and word not in _DOMAIN_GENERIC
                ):
                    tokens.append(word)
        else:
            # 回退：2-gram + 胶水字过滤（跨词边界伪词抑制）
            for i in range(len(seg) - 1):
                bigram = seg[i : i + 2]
                if bigram in _STOPWORDS:
                    continue
                if bigram[0] in _GLUE_CHARS or bigram[1] in _GLUE_CHARS:
                    continue
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
    frequency: int  # 该词在 reconcile 事实中的出现次数（= df，贡献事实数）
    score: float = 0.0  # 综合质量评分（IDF × √df × 形态学权重）
    tf_total: int = 0  # 全库出现总次数（per-fact 内 min(count,3) 截断后累加；作 score 并列时的 tie-breaker）
    representative_title: str = ""  # 代表事实的标题（词密度最高的那条）
    representative_content: str = ""  # 代表事实正文（索引层摘要，截断版）
    suggested_category: str = ""  # 映射后的 kb category
    source_trace: str = (
        ""  # 溯源指针：fact 的 id（如 opencode:ses_x:msg_y），供 agenote trace 回查原始完整对话
    )
    source_facts: list[str] = field(
        default_factory=list
    )  # 贡献该词的事实 id 列表（溯源）


@dataclass
class DreamReport:
    """一次 dream 运行报告。"""

    window_days: int
    total_reconcile_facts: int = 0
    used_facts: int = 0  # 实际参与评分的事实数（window_days 过滤后）
    total_candidates: int = 0  # 不受 offset/limit 截断的完整候选数
    offset: int = 0  # 本次请求的偏移量
    limit: int = DEFAULT_LIMIT  # 本次请求的返回上限
    snapshot_hash: str = ""  # 本次候选集指纹（前 8 位）；offset>0 时提示排序可能漂移
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


def _term_density(term: str, content: str) -> float:
    """该词在 fact 正文中的出现密度（次/百字）。

    用于 representative 选择：密度高说明这条 fact 真的在讨论这个词，
    而非正文很长但只是顺带提到（旧实现按正文长度选，会选到无关大段转录）。
    """
    if not content:
        return 0.0
    return content.count(term) / (len(content) / 100.0)


def _kb_covered_titles() -> set[str]:
    """收集 KB（agenote experiences/）已有卡片标题，用于"KB 已覆盖 → 跳过"判断。

    dream 只补缺口，不复制。旧实现把整张卡片正文都 tokenize 进集合，粒度过粗：
    KB 卡片提过一次 "repo"，全库所有含 "repo" 的候选词都被判覆盖。
    现改为只收标题——只有候选词**正好等于**某张 KB 卡片标题时才判覆盖。
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
        # org 标题行：* DONE <title> / * TODO <title>
        m = re.search(r"^\* (?:DONE|TODO) (.+)$", txt, re.MULTILINE)
        if m:
            titles.add(m.group(1).strip().casefold())
    return titles


# 噪声过滤复用 core 的单一真相源（与 reconcile 写入层一致）。
# dream 这里是二次兜底——reconcile 已在写入层过滤，但 load_reconcile_facts
# 读的是已落盘索引，旧数据可能含未过滤的噪声。
_is_system_content = is_noise_fact


def _gather_candidates(
    facts: list[dict],
    offset: int = 0,
    limit: int = DEFAULT_LIMIT,
    window_days: int = DEFAULT_WINDOW_DAYS,
) -> tuple[list[DreamCandidate], int, int, str]:
    """从 reconcile 事实启发式提取候选。

    评分策略（IDF + 形态学，TF 作 tie-breaker）：
    1. 按 window_days 过滤事实（无 timestamp 的默认保留，如 hermes）
    2. 对幸存事实正文 token 化，统计词频（**保留 per-fact TF**，旧实现去重成 set 丢了 TF）
    3. 用 _term_quality_score 打分：IDF × √df × 形态学权重
       （代码标识符加分，CJK 二字词降权）。**TF 不进主评分**——实测让 TF 进 BM25
       saturation 会使 df=5 长尾词涌入 top（见实证：top-20 恶化成 折叠/nur/welcome），
       因为本项目的好词（项目标识符）通常每条 fact 只出现 1 次，而 BM25 给单 fact 内
       重复词加分。TF 仅在 score 并列时作 tie-breaker（消除随机排序）。
    4. 剔除 KB 已有同名标题的词（精确匹配，非 token 级——实测 token 级误杀好候选）
    5. 每个候选选词密度最高的 fact 作代表（密度高=真的在讨论这个词）

    Args:
        facts: reconcile 事实列表
        offset: 跳过前 N 个候选（用于多轮抽取跳过噪声词）
        limit: 本次最多返回 N 个候选
        window_days: 回看窗口（天）；0=不过滤。无 timestamp 的 fact 不受影响

    Returns:
        (candidates, total_count, used_facts, snapshot_hash) —
        total_count 是截断前候选总数，used_facts 是实际参与评分的事实数（窗口过滤后），
        snapshot_hash 是候选集指纹（前 8 位 hex），供 offset 漂移提示用。
    """
    # ── 时间窗口过滤 ──
    cutoff = None
    if window_days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    usable: list[dict] = []
    for fact in facts:
        ts = _parse_timestamp(fact.get("timestamp", ""))
        if ts is None:
            # 无 timestamp（hermes 等）：默认保留，不因缺数据被误杀
            usable.append(fact)
            continue
        if cutoff is not None and ts < cutoff:
            continue
        usable.append(fact)
    total_facts = len(usable)

    # 词 → [(fact_idx, fact), ...]：记录每个词出现在哪些事实
    # 同时累计 TF（per-fact 内 min(count,3) 截断防单条 fact 刷频次）。
    # 旧实现用 set() 去重把 TF 全丢了——这里保留，仅作 tie-breaker，不进主评分。
    term_facts: dict[str, list[tuple[int, dict]]] = {}
    term_tf_total: dict[str, int] = {}
    for idx, fact in enumerate(usable):
        if _is_system_content(fact):
            continue
        title = fact.get("title", "")
        # Skip facts with useless titles
        if not title or title in ("Untitled", "---", "<system-reminder>", "TASK"):
            continue
        content = fact.get("content", "")
        if len(content) < MIN_FACT_LEN:
            continue
        # 保留 per-fact TF：content + title 合并计数，单 fact 内 min(cnt, 3) 截断
        fact_tf = Counter(_tokenize(content) + _tokenize(title))
        for tok, cnt in fact_tf.items():
            term_facts.setdefault(tok, []).append((idx, fact))
            term_tf_total[tok] = term_tf_total.get(tok, 0) + min(cnt, 3)

    covered = _kb_covered_titles()
    candidates: list[tuple[float, int, DreamCandidate]] = []
    for term, hits in term_facts.items():
        df = len(hits)
        if df < MIN_TERM_FREQ:
            continue
        if term.casefold() in covered:
            continue
        # 选词密度最高的事实作代表：密度高=真的在讨论这个词，而非顺带提及
        # （旧实现选正文最长，但最长往往是无关系的大段转录）
        rep = max(
            hits,
            key=lambda h: _term_density(term, h[1].get("content", "")),
        )[1]
        # Skip if representative is system content（二次兜底）
        if _is_system_content(rep):
            continue
        # 综合评分（IDF × √df × 形态学权重）——主评分
        score = _term_quality_score(term, df, total_facts)
        tf = term_tf_total.get(term, 0)
        candidates.append(
            (
                score,
                tf,
                DreamCandidate(
                    term=term,
                    frequency=df,
                    score=score,
                    tf_total=tf,
                    representative_title=rep.get("title", term),
                    representative_content=rep.get("content", ""),
                    suggested_category=rep.get("category", "general"),
                    source_trace=rep.get("id", ""),
                    source_facts=[h[1].get("id", "") for h in hits],
                ),
            )
        )

    # 排序：score 降序为主，TF 降序作 tie-breaker（消除并列 score 的随机排序）。
    # 例：c-c(df=27) 与 emacs-config(df=21) 的 score 可能并列，此时 TF 高者优先。
    candidates.sort(key=lambda x: (x[0], x[1]), reverse=True)
    total = len(candidates)

    # 候选集指纹：对 (term, df, score) 元组列表算 hash，供 offset 漂移提示。
    # offset 语义不稳定（排序随 reconcile 索引更新变化），指纹让调用方感知"快照已变"。
    fingerprint = "\n".join(
        "%s|%d|%.4f" % (c[2].term, c[2].frequency, c[0]) for c in candidates
    )
    snapshot_hash = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()[:8]

    sliced = [c[2] for c in candidates[offset : offset + limit]]
    return sliced, total, total_facts, snapshot_hash


def run_dream(
    window_days: int = DEFAULT_WINDOW_DAYS,
    dry_run: bool = True,
    offset: int = 0,
    limit: int = DEFAULT_LIMIT,
) -> DreamReport:
    """跑一次 dream（启发式 memory consolidation）。

    Args:
        window_days: 事实时间窗口（天）。0=不过滤看全量；默认 90d（幸存 ~90% facts）。
            无 timestamp 的事实（如 hermes）不受窗口影响，默认保留。
        dry_run: 历史参数，**已无实际效果**——dream 现为纯只读候选发现器，
            不再自动写 KB。保留以兼容 MCP 签名。显式传 `dry_run=False`（旧行为：
            "写 KB"）会触发 DeprecationWarning，提示该参数已废弃。
        offset: 跳过前 N 个候选（用于多轮抽取跳过噪声词）。**注意 offset 语义不稳定**：
            候选排序随 reconcile 索引更新变化，同一 offset 在不同时间可能指向不同候选。
            report.snapshot_hash 标识本次候选集指纹，两次调用指纹不同即说明排序已漂移。
        limit: 本次最多返回 N 个候选（默认 5）

    Returns:
        DreamReport。**零候选是合法返回**（message 说明"无待 consolidate 事实"）。
        有候选时 report.candidates 含代表事实正文 + source_trace 溯源指针——
        agent 对某候选词感兴趣时，用 `agenote trace --id <source_trace>` 读该词
        出现的完整原始对话（含工具调用/推理/补丁，索引层摘要不截断），
        再用 agenote_add 决定是否综合写入 KB（见 agenote-curator skill Step 3）。
    """
    # dry_run 弃用警告：只在显式传 dry_run=False（旧行为）时触发。
    # 默认 dry_run=True 不警告（避免每次调用都吵）——只提示那些以为"False=写KB"的调用方。
    if dry_run is False:
        warnings.warn(
            "run_dream(dry_run=False) 已无效果——dream 现为纯只读候选发现器，"
            "不再自动写 KB。该参数保留仅为向后兼容，请勿依赖其行为。",
            DeprecationWarning,
            stacklevel=2,
        )

    report = DreamReport(window_days=window_days, offset=offset, limit=limit)
    facts = load_reconcile_facts()
    report.total_reconcile_facts = len(facts)

    if not facts:
        report.message = (
            "无待 consolidate 事实（reconcile 索引为空，先跑 agenote_reconcile）"
        )
        return report

    candidates, total, used_facts, snapshot_hash = _gather_candidates(
        facts, offset=offset, limit=limit, window_days=window_days
    )
    report.total_candidates = total
    report.used_facts = used_facts
    report.snapshot_hash = snapshot_hash

    if not candidates:
        if total == 0:
            report.message = (
                "无候选：%d 条事实（窗口 %dd）中没有 ≥%d 次出现且 KB 未覆盖的主题"
                "（零产物即成功）" % (used_facts, window_days, MIN_TERM_FREQ)
            )
        else:
            report.message = (
                "偏移 %d 已超出候选总数 %d（无更多候选）。"
                "可尝试 --offset 0 从头查看，或减小 offset。" % (offset, total)
            )
        return report

    report.candidates = [asdict(c) for c in candidates]
    remaining = total - offset - len(candidates)
    window_note = "（窗口 %dd，%d/%d 条事实参与）" % (
        window_days,
        used_facts,
        report.total_reconcile_facts,
    )
    trace_hint = (
        "对某候选感兴趣时用 `agenote trace --id <source_trace>` 读完整原始对话"
        "（含工具调用/推理/补丁）。dream 不自动写 KB——agent 综合流程见 "
        "agenote-curator skill 的 'Step 3 — Agent 综合'。"
    )
    # offset 漂移提示：offset>0 时排序可能已变，提示调用方核对 snapshot_hash。
    drift_hint = (
        "\n⚠ offset 漂移：候选排序随 reconcile 索引更新变化，本次基于 snapshot %s。"
        "下次调用若 snapshot 变了，offset 指向的内容可能不同。"
        % snapshot_hash
    )
    if remaining > 0:
        report.message = (
            "发现 %d/%d 个候选（第 %d-%d 个%s，共 %d 个，snapshot %s）。"
            "还有 %d 个候选未显示，可用 --offset %d 继续查看。%s%s"
            % (
                len(candidates),
                total,
                offset + 1,
                offset + len(candidates),
                window_note,
                total,
                snapshot_hash,
                remaining,
                offset + len(candidates),
                trace_hint,
                drift_hint if offset > 0 else "",
            )
        )
    else:
        report.message = (
            "发现 %d/%d 个候选（第 %d-%d 个%s，全部候选已显示，snapshot %s）。\n%s%s"
            % (
                len(candidates),
                total,
                offset + 1,
                offset + len(candidates),
                window_note,
                snapshot_hash,
                trace_hint,
                drift_hint if offset > 0 else "",
            )
        )
    return report
