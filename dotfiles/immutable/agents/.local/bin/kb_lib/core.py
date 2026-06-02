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
KB_PATTERNS = KB_MEMORY  # 向后兼容别名（patterns 已合并到 MEMORY）
KB_INDEX = KB_ROOT / "index.json"  # JSON 查询索引
KB_INBOX = KB_ROOT / "inbox.org"  # 快速捕获收件箱
KB_PROFILE = KB_ROOT / "profile.org"  # 用户画像文件

VALID_TYPES = {"debug", "refactor", "research", "workflow", "feature", "config"}
VALID_OWNERS = {"human", "ai", "collab"}
VALID_ENTRY_TYPES = {"mistake", "note", "ascended"}

# ── 阈值 ──────────────────────────────────────────────────────────────────────
STALE_DAYS = 30  # 记忆条目超过此天数未更新视为陈旧
DEFAULT_LIST_COUNT = 20  # kb list 默认显示条数

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


def _init_memory_template() -> None:
    """从零生成 MEMORY.org 模板，包含所有标准节。"""
    date_str = datetime.now().strftime("%Y-%m-%d %a")
    sections = [f"#+title: MEMORY", f"#+date: [{date_str}]"]
    sections.append("")
    sections.append("#+BEGIN_COMMENT")
    sections.append("MEMORY.org — 统一记忆索引")
    sections.append("")
    sections.append("设计原则：")
    sections.append("1. 记忆只存储无法从当前代码/项目状态推导的信息")
    sections.append("2. feedback 记录用户的行为偏好和工作癖好")
    sections.append("3. project 记忆按项目拆分为独立文件，通过路径/名称检索")
    sections.append("4. 记忆是时间点观察，不是实时状态——引用前先验证")
    sections.append("5. MEMORY 偏重癖好偏好，知识库偏重可复用知识")
    sections.append("6. 带 ⚠ 标记的条目为陈旧记忆，需验证后才能作为决策依据")
    sections.append("#+END_COMMENT")
    for sec in MEMORY_SECTIONS:
        sections.append("")
        sections.append(f"* {sec}")
    KB_MEMORY.write_text("\n".join(sections) + "\n", encoding="utf-8")


def _init_profile(filepath: Path) -> None:
    """初始化用户画像模板。仅生成骨架，具体内容由 AI 在对话中总结后写入。"""
    filepath.write_text(
        f"""#+title: 用户画像
#+date: [{datetime.now().strftime('%Y-%m-%d %a')}]

#+BEGIN_COMMENT
<critical>
若以上的 ~date 距离当前日期超过七天，那么请务必一定要进行一次用户画像的更新。
</critical>

更新步骤见：~/.config/agents/skills/self-improving/SKILL.md
#+END_COMMENT

* 身份

* 偏好

* 习惯

* 活跃项目

* 目标
""",
        encoding="utf-8",
    )


def ensure_dirs() -> None:
    """确保知识库目录和基础文件存在。

    自愈机制：所有目录和模板文件在缺失时自动重建。
    删除任意文件或整个 KB_ROOT 后重新运行 kb 命令即可恢复骨架。
    注意：仅重建结构，不恢复卡片内容。
    """
    # ── 目录 ────────────────────────────────────────────────────────────────
    KB_EXPERIENCES.mkdir(parents=True, exist_ok=True)
    KB_MEMORIES.mkdir(parents=True, exist_ok=True)
    KB_PROJECTS.mkdir(parents=True, exist_ok=True)

    # ── inbox.org ──────────────────────────────────────────────────────────
    if not KB_INBOX.exists():
        KB_INBOX.write_text(
            f"#+title: inbox\n#+date: [{now()}]\n\n",
            encoding="utf-8",
        )

    # ── MEMORY.org（含所有标准节）──────────────────────────────────────────
    if not KB_MEMORY.exists():
        _init_memory_template()

    # ── profile.org（用户画像骨架）────────────────────────────────────────
    if not KB_PROFILE.exists():
        _init_profile(KB_PROFILE)

    # ── index.json（空索引）────────────────────────────────────────────────
    if not KB_INDEX.exists():
        _save_index({"version": 1, "updated": "", "total": 0, "cards": []})


def parse_org_prop(content: str, key: str) -> str:
    """从 Org 文件内容中提取 PROPERTIES 块中的指定属性值。"""
    m = re.search(rf":{key}:\s*(.+)", content)
    return m.group(1).strip() if m else ""


def read_org_title(content: str) -> str:
    """从 Org 内容中提取一级标题文本（去掉 DONE/TODO 前缀）。"""
    m = re.search(r"^\* (?:DONE|TODO) (.+)", content, re.MULTILINE)
    return m.group(1).strip() if m else "unknown"


def _card_dict(filepath: Path) -> dict | None:
    """从一张卡片文件提取索引条目，返回 dict 或 None。

    跳过符号链接（避免索引 Guix store 中的重复文件）。
    tags 字段按逗号展开，解决 tech 含逗号时的数据污染问题。
    """
    if filepath.is_symlink():
        return None
    content = filepath.read_text(encoding="utf-8")
    card_id = parse_org_prop(content, "ID") or filepath.stem.split("-")[0]
    created = parse_org_prop(content, "CREATED")
    if created:
        created = re.sub(r"[\[\]]", "", created).split()[0]
    entry_type = parse_org_prop(content, "ENTRY_TYPE") or None

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
        "file": str(filepath.relative_to(KB_ROOT)),
        "title": read_org_title(content),
        "category": parse_org_prop(content, "CATEGORY") or "general",
        "tech": parse_org_prop(content, "TECH") or "",
        "type": parse_org_prop(content, "TYPE") or "workflow",
        "owner": parse_org_prop(content, "OWNER") or "ai",
        "entry_type": entry_type,
        "status": parse_org_prop(content, "STATUS") or "done",
        "last_used": parse_org_prop(content, "LAST_USED"),
        "last_verified": parse_org_prop(content, "LAST_VERIFIED"),
        "created": created or "",
        "tags": expanded_tags,
    }


def _load_index() -> dict:
    """加载 JSON 索引，失败返回空骨架。"""
    if KB_INDEX.exists():
        try:
            return json.loads(KB_INDEX.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {"version": 1, "updated": "", "total": 0, "cards": []}


def _save_index(index: dict) -> None:
    """写入 JSON 索引。"""
    index["updated"] = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    index["total"] = len(index["cards"])
    KB_INDEX.write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _rebuild_index() -> dict:
    """全量扫描 experiences/ 重建索引 dict。"""
    cards = []
    for f in sorted(
        KB_EXPERIENCES.rglob("*.org"), key=lambda p: p.stat().st_mtime, reverse=True
    ):
        d = _card_dict(f)
        if d:
            cards.append(d)
    return {"version": 1, "updated": "", "total": len(cards), "cards": cards}


def _upsert_card(index: dict, filepath: Path) -> None:
    """增量更新：插入或替换一张卡片到索引。"""
    d = _card_dict(filepath)
    if not d:
        return
    for i, c in enumerate(index["cards"]):
        if c["id"] == d["id"]:
            index["cards"][i] = d
            break
    else:
        index["cards"].insert(0, d)


def _iter_search_targets() -> list[Path]:
    """返回全文检索目标文件。"""
    targets = []
    if KB_EXPERIENCES.exists():
        targets.extend(
            f
            for f in sorted(KB_EXPERIENCES.rglob("*.org"))
            if f.is_file() and not f.is_symlink()
        )
    if KB_MEMORY.exists():
        targets.append(KB_MEMORY)
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

# MEMORY-ARCHIVE.org 路径
KB_MEMORY_ARCHIVE = KB_ROOT / "MEMORY-ARCHIVE.org"


# ═══════════════════════════════════════════════════════════════════════════════
# 卡片级操作
# ═══════════════════════════════════════════════════════════════════════════════


def touch_card(filepath: Path, field: str = "LAST_USED") -> None:
    """更新卡片 PROPERTIES 中的指定时间戳字段，同步更新 index.json。

    Args:
        filepath: 卡片文件路径
        field: 要更新的字段名（LAST_USED 或 LAST_VERIFIED）
    """
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
    filepath.write_text(content, encoding="utf-8")

    # 同步更新索引
    index = _load_index()
    _upsert_card(index, filepath)
    _save_index(index)


def _resolve_card(id_or_path: str) -> Path | None:
    """通过 ID 或文件名解析卡片路径。"""
    p = Path(id_or_path)
    if p.is_file():
        return p
    candidates = list(KB_EXPERIENCES.rglob(f"*{id_or_path}*"))
    # 过滤掉符号链接，只返回实际文件
    candidates = [c for c in candidates if not c.is_symlink()]
    return candidates[0] if candidates else None
