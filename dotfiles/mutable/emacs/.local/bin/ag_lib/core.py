# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

"""kb_core — 知识库核心模块：常量、工具函数、索引管理、Org 解析、搜索辅助"""

import json
import os
import re
import shlex
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

# ═══════════════════════════════════════════════════════════════════════════════
# 配置常量 — 所有可变参数集中在此，修改时只需改这里
# ═══════════════════════════════════════════════════════════════════════════════

# ── 路径 ──────────────────────────────────────────────────────────────────────
KB_ROOT = Path(
    os.environ.get("KB_ROOT", str(Path.home() / "Documents" / "Org"))
)  # 知识库根目录
KB_EXPERIENCES = KB_ROOT / "experiences"  # 经验卡片存储目录
KB_MEMORY = KB_ROOT / "MEMORY.org"  # 记忆文件（feedback/project/reference）
KB_MEMORIES = KB_ROOT / "memories"  # 记忆子目录
KB_PROJECTS = KB_MEMORIES / "projects"  # 项目记忆文件目录
KB_INDEX = KB_ROOT / "index.json"  # JSON 查询索引
KB_INBOX = KB_ROOT / "inbox.org"  # 快速捕获收件箱
KB_MEMORY_ARCHIVE = KB_ROOT / "MEMORY-ARCHIVE.org"  # feedback 归档文件

VALID_TYPES = {"debug", "refactor", "research", "workflow", "feature", "config"}
VALID_OWNERS = {"human", "ai", "collab"}
VALID_ENTRY_TYPES = {"mistake", "note", "ascended"}

# ── source_agent 体系（跨 agent 经验溯源）─────────────────────────────────────
# 记录每张卡片由哪个 agent 写入，供跨 agent 检索/健康度统计/reconcile 使用。
# 写入时从 os.environ["AGENOTE_AGENT"] 取值；人类手写的卡片留空（source_agent=""）。
# 白名单用于 sanity check（缺失或不在白名单只警告，不阻塞，便于新增 agent）。
KNOWN_AGENTS = {
    "pi",  # pi-coding-agent（agenote-hooks 自动写入）
    "hermes",  # hermes-agent
    "omp",  # oh-my-pi（用户偏好暂不托管，预留）
    "crush",  # crush agent
    "opencode",  # opencode fork
    "mimocode",  # MiMoCode（opencode fork）
    "claude-code",  # claude-code
    "zcode",  # zcode agent (GLM-based)
    "pi-dream",  # dream 工作流产生的卡片（系统生成）
    "pi-distill",  # distill 工作流产生的卡片（系统生成）
}

# AGENOTE_AGENT 环境变量名（各 agent 的 MCP 启动入口需设置）
AGENT_ENV_VAR = "AGENOTE_AGENT"
# 兜底默认值：未设置环境变量时（如人类直接 kb add）记为 pi，保持向后兼容
DEFAULT_AGENT = "pi"


def default_agent() -> str:
    """读取当前调用者所属 agent 名。

    优先取 AGENOTE_AGENT 环境变量；缺失时回退 DEFAULT_AGENT（"pi"）。
    空/只空白视为未设置（回退默认值），避免 SOURCE_AGENT 写成空串。
    """
    val = os.environ.get(AGENT_ENV_VAR, "").strip()
    return val or DEFAULT_AGENT


# ── reconcile 噪声过滤（系统消息/工具提示，非用户知识）──────────────────────
# reconcile 写入层用；dream 复用避免重复统计。
# 覆盖 TodoWrite、background-task、system-reminder、checkpoint、command-* 等
# "元消息"——它们源自 harness 注入而非用户的真实经验。
NOISE_MARKERS = re.compile(
    r"<system-reminder>|<command-instruction>|<command-name>|"
    r"<skill-instruction>|<auto-slash-command>|"
    r"\[search-mode\]|\[analyze-mode\]|\[SYSTEM DIRECTIVE"
    r"|TodoWrite|BACKGROUND TASK|OMO_INTERNAL_INITIATOR|"
    r"delegate_task|subagent_type|run_in_background|"
    r"load_skills|checkpoint|MANDATORY",
    re.IGNORECASE,
)
NOISE_MIN_LEN = 15  # <15 字符的事实视为无信息量（沿用 dream.py 旧 MIN_FACT_LEN）


def is_noise_fact(fact: dict) -> bool:
    """判别 reconcile 事实是否为元消息/工具提示噪声。

    元消息（TodoWrite 提示、[search-mode]、system-reminder、checkpoint 等）源自
    harness 注入，不是用户的真实经验。它们常以 `USER: <元消息>\\n\\nASSISTANT: <真实回复>`
    的形态出现——整条 content 可能很长（ASSISTANT 段有内容），但**用户提问的开头**
    是元消息。因此按全文长度做密度阈值（旧 /100、/300）会漏检。

    判定规则（任一即噪声）：
    1. content+title 总长 < NOISE_MIN_LEN（信息量不足）
    2. title 本身命中 NOISE_MARKERS（纯元消息标题，如 `[search-mode]`）
    3. content 的**开头 250 字符**（USER 提问区）命中 ≥1 个 NOISE_MARKERS
       ——真实对话的 marker 常出现在 assistant 回复中段（被保留），只有用户提问
       本身是元消息时才判噪。
    """
    content = fact.get("content", "") or ""
    title = fact.get("title", "") or ""
    if len(content) + len(title) < NOISE_MIN_LEN:
        return True
    if NOISE_MARKERS.search(title):
        return True
    return bool(NOISE_MARKERS.search(content[:250]))


# ── 阈值 ──────────────────────────────────────────────────────────────────────
STALE_DAYS = 30  # 记忆条目超过此天数未更新视为陈旧
DEFAULT_LIST_COUNT = 20  # kb list 默认显示条数

# ── agenote 权重系统 ──────────────────────────────────────────────────────────
HUMAN_DEFAULT_WEIGHT = 1.5  # 人类卡片默认检索权重
AGENT_DEFAULT_WEIGHT = 1.0  # agent 卡片默认检索权重
WEIGHT_USAGE_BONUS = 0.1  # 每次 touch 的权重提升系数
WEIGHT_USAGE_CAP = 10  # 使用次数提升上限（×0.1 → 最多 +1.0）
WEIGHT_STALE_PENALTY = 0.8  # 超过 STALE_DAYS 未用的权重惩罚系数

MEMORY_SECTIONS = ["feedback", "project", "reference", "deprecated"]

# 每个模板是一个行列表，用于 cmd_add 生成新卡片
CARD_TEMPLATES = {
    "mistake": [
        "** 执行过程",
        None,  # 占位符：运行时替换为 body 或默认内容
        "",
        "** 关键发现",
        "*** 下次开始前自检",
        "",
        "** 难点与坑点 :difficulties:",
        "",
        "** 经验教训 :lessons:",
        "",
        "** 相关链接",
        "",
        "** AI 建议 :ai_notes:",
    ],
    "note": [
        "** 执行过程",
        None,
        "",
        "** 关键发现",
        "",
        "** 难点与坑点 :difficulties:",
        "",
        "** 经验教训 :lessons:",
        "",
        "** 相关链接",
        "",
        "** AI 建议 :ai_notes:",
    ],
    "ascended": [
        "** 执行过程",
        None,
        "",
        "** 关键发现",
        "*** 需要新增或修补的规则",
        "",
        "** 难点与坑点 :difficulties:",
        "",
        "** 经验教训 :lessons:",
        "",
        "** 相关链接",
        "",
        "** AI 建议 :ai_notes:",
    ],
    "default": [
        "** 执行过程",
        None,  # 占位符：运行时替换为 body 或 "1. "
        "",
        "** 难点与坑点 :difficulties:",
        "",
        "** 经验教训 :lessons:",
        "",
        "** 相关链接",
        "",
        "** AI 建议 :ai_notes:",
    ],
}

# 各 entry_type 的默认 body 占位内容
ENTRY_BODY_DEFAULTS = {
    "mistake": "*** 原始问题\n\n*** 用户纠错反馈\n\n*** 这次到底错在哪里\n\n*** 最终正确处理\n",
    "note": "*** 事项内容\n\n*** 为什么值得长期保留\n\n*** 适用场景与例外\n\n*** 后续行动\n",
    "ascended": "*** 前几轮失败的根因\n\n*** 检索过的知识源\n\n*** 核对过的真实文件或输出\n\n*** 最终采用的最强方案\n",
    "default": "1. ",
}


# ═══════════════════════════════════════════════════════════════════════════════
# KBContext — 路径上下文封装（人类 / agenote 共享实现的基础）
# ═══════════════════════════════════════════════════════════════════════════════


@dataclass
class KBContext:
    """封装一个知识库域的全部路径。

    人类域用 default_context()，agent 域用 agenote_context()。
    所有 cmd_* 与辅助函数接受可选 ctx 参数，None 时回退到 default_context()。
    """

    name: str  # 域名（"human" / "agenote"）
    root: Path  # 该域根目录
    experiences: Path  # experiences/ 目录
    memories: Path  # memories/ 目录
    projects: Path  # memories/projects/ 目录
    memory_org: Path  # MEMORY.org 路径
    memory_archive: Path  # MEMORY-ARCHIVE.org 路径
    index: Path  # index.json 路径
    inbox: Path  # inbox.org 路径
    is_human: bool = True  # 是否人类域（影响 MEMORY 模板文案、curate 基础权重选择）
    default_weight: float = 1.5  # 该域卡片默认检索权重
    agent_name: str = ""  # 写入卡片时打的 source_agent 标签（default_context 留空）


def default_context() -> KBContext:
    """人类知识库上下文（KB_ROOT 根，权重 1.5）。

    人类域的 agent_name 留空（""），区分"人手写"与"agent 写"。
    """
    return KBContext(
        name="human",
        root=KB_ROOT,
        experiences=KB_EXPERIENCES,
        memories=KB_MEMORIES,
        projects=KB_PROJECTS,
        memory_org=KB_MEMORY,
        memory_archive=KB_MEMORY_ARCHIVE,
        index=KB_INDEX,
        inbox=KB_INBOX,
        is_human=True,
        default_weight=HUMAN_DEFAULT_WEIGHT,
        agent_name="",
    )


def agenote_context(agent_name: str | None = None) -> KBContext:
    """agenote 上下文（KB_ROOT/agenote 子目录，权重 1.0）。

    首次调用不创建目录——由 cmd_agenote_init / ensure_dirs(ctx) 负责。

    agent_name 决定该上下文写入卡片时的 SOURCE_AGENT 标签：
    - 显式传参时用传入值（便于 dream/distill 等系统工作流标记自身）
    - 否则读 AGENOTE_AGENT 环境变量（MCP 启动入口设置）
    - 都缺失时回退 DEFAULT_AGENT（"pi"），保持向后兼容
    """
    root = KB_ROOT / "agenote"
    return KBContext(
        name="agenote",
        root=root,
        experiences=root / "experiences",
        memories=root / "memories",
        projects=root / "memories" / "projects",
        memory_org=root / "MEMORY.org",
        memory_archive=root / "MEMORY-ARCHIVE.org",
        index=root / "index.json",
        inbox=root / "inbox.org",
        is_human=False,
        default_weight=AGENT_DEFAULT_WEIGHT,
        agent_name=agent_name if agent_name is not None else default_agent(),
    )


def _build_template(entry_type: str, body: str) -> list[str]:
    """根据 entry_type 生成对应的模板章节。

    模板定义在 CARD_TEMPLATES 常量中，此处查找对应模板并填充 body。
    """
    # 选择模板：优先精确匹配 entry_type，否则用 default
    template = CARD_TEMPLATES.get(entry_type, CARD_TEMPLATES["default"])
    # 选择默认 body 内容
    default_body = ENTRY_BODY_DEFAULTS.get(entry_type, ENTRY_BODY_DEFAULTS["default"])

    result = []
    for line in template:
        if line is None:
            # None 是 body 占位符：运行时替换为实际内容
            result.append(body or default_body)
        else:
            result.append(line)
    return result


# ═══════════════════════════════════════════════════════════════════════════════
# 工具函数
# ═══════════════════════════════════════════════════════════════════════════════


def die(msg: str) -> None:
    """打印错误信息并退出。"""
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(1)


def now() -> str:
    """返回当前时间字符串，格式：2026-05-05 一 15:30"""
    return datetime.now().strftime("%Y-%m-%d %a %H:%M")


def today() -> str:
    """返回当前日期字符串，格式：2026-05-05"""
    return datetime.now().strftime("%Y-%m-%d")


def timestamp_id() -> str:
    """生成时间戳 ID，格式：20260505-153000"""
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def _init_memory_template_for_ctx(ctx: "KBContext") -> None:
    """为指定 ctx 生成 MEMORY.org 模板（参数化版 _init_memory_template）。

    人类域与 agent 域的 MEMORY 文案略有差异（feedback 节语义不同）。
    """
    date_str = datetime.now().strftime("%Y-%m-%d %a")
    sections = [f"#+title: MEMORY-{ctx.name}", f"#+date: [{date_str}]"]
    sections.append("")
    sections.append("#+BEGIN_COMMENT")
    sections.append(f"MEMORY.org — {ctx.name} 记忆索引")
    sections.append("")
    sections.append("设计原则：")
    sections.append("1. 记忆只存储无法从当前代码/项目状态推导的信息")
    if ctx.is_human:
        sections.append("2. feedback 记录用户的行为偏好和工作癖好")
    else:
        sections.append("2. feedback 记录用户对 agent 工作方式的偏好")
    sections.append("3. project 记忆按项目拆分为独立文件，通过路径/名称检索")
    sections.append("4. 记忆是时间点观察，不是实时状态——引用前先验证")
    sections.append("#+END_COMMENT")
    for sec in MEMORY_SECTIONS:
        sections.append("")
        sections.append(f"* {sec}")
    ctx.memory_org.write_text("\n".join(sections) + "\n", encoding="utf-8")


def ensure_dirs(ctx: "KBContext | None" = None) -> None:
    """确保知识库目录和基础文件存在。

    自愈机制：所有目录和模板文件在缺失时自动重建。
    删除任意文件或整个 KB_ROOT 后重新运行 kb 命令即可恢复骨架。
    注意：仅重建结构，不恢复卡片内容。
    """
    ctx = ctx or default_context()
    # ── 目录 ────────────────────────────────────────────────────────────────
    ctx.experiences.mkdir(parents=True, exist_ok=True)
    ctx.memories.mkdir(parents=True, exist_ok=True)
    ctx.projects.mkdir(parents=True, exist_ok=True)

    # ── inbox.org ──────────────────────────────────────────────────────────
    if not ctx.inbox.exists():
        ctx.inbox.write_text(
            f"#+title: inbox\n#+date: [{now()}]\n\n",
            encoding="utf-8",
        )

    # ── MEMORY.org（含所有标准节）──────────────────────────────────────────
    if not ctx.memory_org.exists():
        _init_memory_template_for_ctx(ctx)

    # ── index.json（空索引）────────────────────────────────────────────────
    if not ctx.index.exists():
        _save_index({"version": 1, "updated": "", "total": 0, "cards": []}, ctx)


def parse_org_prop(content: str, key: str) -> str:
    """从 Org 文件内容中提取 PROPERTIES 块中的指定属性值。"""
    m = re.search(rf":{key}:\s*(.+)", content)
    return m.group(1).strip() if m else ""


def _parse_float_prop(content: str, key: str, default: float) -> float:
    """从 PROPERTIES 解析浮点字段，缺失返回 default。"""
    raw = parse_org_prop(content, key)
    if not raw:
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _parse_int_prop(content: str, key: str, default: int) -> int:
    """从 PROPERTIES 解析整数字段，缺失返回 default。"""
    raw = parse_org_prop(content, key)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def read_org_title(content: str) -> str:
    """从 Org 内容中提取一级标题文本（去掉 DONE/TODO 前缀）。"""
    m = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    return m.group(1).strip() if m else "unknown"


def _card_dict(filepath: Path, ctx: "KBContext | None" = None) -> dict | None:
    """从一张卡片文件提取索引条目，返回 dict 或 None。

    跳过符号链接（避免索引 Guix store 中的重复文件）。
    tags 字段按逗号展开，解决 tech 含逗号时的数据污染问题。
    """
    ctx = ctx or default_context()
    if filepath.is_symlink():
        return None
    content = filepath.read_text(encoding="utf-8")
    card_id = parse_org_prop(content, "ID") or filepath.stem.split("-")[0]
    created = parse_org_prop(content, "CREATED")
    if created:
        created = re.sub(r"[\[\]]", "", created).split()[0]
    entry_type = parse_org_prop(content, "ENTRY_TYPE") or None
    # source_agent：记录卡片写入者。旧卡片无此属性 → 空串（迁移时补 pi）。
    source_agent = parse_org_prop(content, "SOURCE_AGENT") or ""

    # ── 解析 tags 行 ─────────────────────────────────────────────────────
    # tags 行格式: ":category:type:owner:tech::"（冒号分隔，尾部双冒号）
    # tech 字段可能含逗号（如 "Hexo,Playwright,GuixSD"），需按逗号展开
    tags_line = ""
    m = re.search(r":(\S+)::", content)
    if m:
        tags_line = m.group(1)
    raw_tags = tags_line.split(":") if tags_line else []
    # 展开含逗号的标签（如 "Hexo,Playwright" → ["Hexo", "Playwright"]）
    expanded_tags = []
    for tag in raw_tags:
        expanded_tags.extend(t.strip() for t in tag.split(",") if t.strip())

    return {
        "id": card_id,
        "file": str(filepath.relative_to(ctx.root)),
        "title": read_org_title(content),
        "category": parse_org_prop(content, "CATEGORY") or "general",
        "tech": parse_org_prop(content, "TECH") or "",
        "type": parse_org_prop(content, "TYPE") or "workflow",
        "owner": parse_org_prop(content, "OWNER") or "ai",
        "entry_type": entry_type,
        "source_agent": source_agent,
        "status": parse_org_prop(content, "STATUS") or "done",
        "last_used": parse_org_prop(content, "LAST_USED"),
        "last_verified": parse_org_prop(content, "LAST_VERIFIED"),
        "created": created or "",
        "tags": expanded_tags,
        "weight": _parse_float_prop(content, "WEIGHT", ctx.default_weight),
        "usage_count": _parse_int_prop(content, "USAGE_COUNT", 0),
    }


def _load_index(ctx: "KBContext | None" = None) -> dict:
    """加载 JSON 索引，失败返回空骨架。"""
    ctx = ctx or default_context()
    if ctx.index.exists():
        try:
            return json.loads(ctx.index.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {"version": 1, "updated": "", "total": 0, "cards": []}


def _save_index(index: dict, ctx: "KBContext | None" = None) -> None:
    """写入 JSON 索引。"""
    ctx = ctx or default_context()
    index["updated"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    index["total"] = len(index["cards"])
    ctx.index.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _rebuild_index(ctx: "KBContext | None" = None) -> dict:
    """全量扫描 experiences/ 重建索引 dict。"""
    ctx = ctx or default_context()
    cards = []
    for f in sorted(
        ctx.experiences.rglob("*.org"), key=lambda p: p.stat().st_mtime, reverse=True
    ):
        d = _card_dict(f, ctx)
        if d:
            cards.append(d)
    return {"version": 1, "updated": "", "total": len(cards), "cards": cards}


def _upsert_card(index: dict, filepath: Path, ctx: "KBContext | None" = None) -> None:
    """增量更新：插入或替换一张卡片到索引。"""
    ctx = ctx or default_context()
    d = _card_dict(filepath, ctx)
    if not d:
        return
    for i, c in enumerate(index["cards"]):
        if c["id"] == d["id"]:
            index["cards"][i] = d
            break
    else:
        index["cards"].insert(0, d)


def _iter_search_targets(ctx: "KBContext | None" = None) -> list[Path]:
    """返回全文检索目标文件。"""
    ctx = ctx or default_context()
    targets = []
    if ctx.experiences.exists():
        targets.extend(
            f
            for f in sorted(ctx.experiences.rglob("*.org"))
            if f.is_file() and not f.is_symlink()
        )
    if ctx.memory_org.exists():
        targets.append(ctx.memory_org)
    return targets


def _query_terms(query: str) -> list[str]:
    """把用户查询拆成适合模糊检索的关键词。"""
    try:
        pieces = shlex.split(query)
    except ValueError:
        pieces = query.split()

    terms = []
    for piece in pieces:
        for term in re.split(r"[/,，、]+", piece):
            term = term.strip()
            if term:
                terms.append(term)
    if not terms and query.strip():
        terms = [query.strip()]

    unique = []
    seen = set()
    for term in terms:
        key = term.casefold()
        if key not in seen:
            seen.add(key)
            unique.append(term)
    return unique


def _line_contains_any(line: str, needles: list[str], case_sensitive: bool) -> bool:
    """判断一行是否包含任一关键词。"""
    haystack = line if case_sensitive else line.casefold()
    return any(needle in haystack for needle in needles)


def _merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """合并上下文行号范围。"""
    if not ranges:
        return []
    ranges = sorted(ranges)
    merged = [ranges[0]]
    for start, end in ranges[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end + 1:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))
    return merged


def _range_score(
    lines: list[str], start: int, end: int, needles: list[str], case_sensitive: bool
) -> int:
    """计算上下文块与查询词的相关度。"""
    block = "\n".join(lines[start : end + 1])
    haystack = block if case_sensitive else block.casefold()
    matched_terms = [needle for needle in needles if needle in haystack]
    return len(matched_terms) * 100 + sum(
        haystack.count(needle) for needle in matched_terms
    )


# ═══════════════════════════════════════════════════════════════════════════════
# 子命令: add — 添加经验卡片
# ═══════════════════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════════════════
# 状态机阈值
# ═══════════════════════════════════════════════════════════════════════════════

STALE_THRESHOLD_DAYS = 30  # stable → stale 阈值（天）
ARCHIVE_THRESHOLD_DAYS = 90  # stale → archived 阈值（天）
MEMORY_ARCHIVE_DAYS = 60  # feedback stale → 归档阈值（天）
VALID_STATUSES = {"done", "stable", "stale", "archived"}


# ═══════════════════════════════════════════════════════════════════════════════
# 卡片级操作
# ═══════════════════════════════════════════════════════════════════════════════


def touch_card(
    filepath: Path, field: str = "LAST_USED", ctx: "KBContext | None" = None
) -> None:
    """更新卡片 PROPERTIES 中的指定时间戳字段，同步更新 index.json。

    Args:
        filepath: 卡片文件路径
        field: 要更新的字段名（LAST_USED 或 LAST_VERIFIED）
        ctx: 知识库上下文（None 时用 default_context）
    """
    ctx = ctx or default_context()
    if not filepath.exists():
        return
    content = filepath.read_text(encoding="utf-8")
    ts = f"[{now()}]"
    if f":{field}:" in content:
        content = re.sub(rf":{field}:\s*\[.+?\]", f":{field}:   {ts}", content)
    else:
        # 在 :STATUS: 行后插入
        if ":STATUS:" in content:
            content = content.replace(f":STATUS:", f":{field}:   {ts}\n:STATUS:", 1)
        else:
            # 在 :END: 前插入
            content = content.replace(":END:", f":{field}:   {ts}\n:END:", 1)
    # 递增 USAGE_COUNT（留痕核心：每次 touch 表示该卡片被实际使用）
    if ":USAGE_COUNT:" in content:
        m = re.search(r":USAGE_COUNT:\s*(\d+)", content)
        if m:
            new_count = int(m.group(1)) + 1
            content = re.sub(
                r":USAGE_COUNT:\s*\d+", f":USAGE_COUNT: {new_count}", content
            )
    else:
        # 旧卡片无此字段，初始化为 1（首次留痕）
        content = content.replace(":END:", ":USAGE_COUNT: 1\n:END:", 1)
    filepath.write_text(content, encoding="utf-8")

    # 同步更新索引
    index = _load_index(ctx)
    _upsert_card(index, filepath, ctx)
    _save_index(index, ctx)


def _resolve_card(id_or_path: str, ctx: "KBContext | None" = None) -> Path | None:
    """通过 ID 或文件名解析卡片路径。"""
    ctx = ctx or default_context()
    p = Path(id_or_path)
    if p.is_file():
        return p
    candidates = list(ctx.experiences.rglob(f"*{id_or_path}*"))
    # 过滤掉符号链接，只返回实际文件
    candidates = [c for c in candidates if not c.is_symlink()]
    return candidates[0] if candidates else None
