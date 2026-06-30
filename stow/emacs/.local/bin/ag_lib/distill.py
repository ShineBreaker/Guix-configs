# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
"""ag_lib.distill — workflow packaging（把重复经验打包成 skill 草稿）。

扫 KB 卡片里**被反复使用的工作流模式**，聚类为候选 skill 草稿，
写到 `.distill/`（**不直接进 skills/ 目录**），人工 review + 手动 move 才生效。

设计原则（从 MiMoCode `agent/prompt/distill.txt` 提炼）：
1. **No extract without evidence**：只有 ≥2 张同主题卡片才聚类为候选，
   没有就明说"无候选"。**零产物即成功**（distill.txt:39-41）。
2. **draft 不进 skills/ 目录**：避免污染 agent 的 skill 列表，人工 move 才生效。
3. **不调 LLM 生成正文**：用 SKILL.md 模板填空（name/description/触发场景），
   正文仍由用户写（distill.txt 不靠模型杜撰步骤）。
4. **幂等**：已存在的同主题 draft 不重复生成（避免每次跑都堆叠）。

聚类维度：category + tech（同技术栈的卡片视为同一工作流候选）。
触发条件：`type == ascended`（经过多轮试错验证的最优方案）或 `usage_count >= 2`。
"""

import re
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

from ag_lib.core import _load_index, agenote_context

# ═══════════════════════════════════════════════════════════════════════════════
# 常量
# ═══════════════════════════════════════════════════════════════════════════════

AGENOTE_ROOT = Path.home() / "Documents" / "Org" / "agenote"
DISTILL_DIR = AGENOTE_ROOT / ".distill"

MIN_CLUSTER_SIZE = 2  # 同 category+tech 至少 N 张卡片才聚类为候选（evidence）
MIN_USAGE_FOR_ASCEND = 2  # usage_count >= N 视为"反复使用"
ASCENDED_TYPE = "ascended"  # 经多轮试错验证的卡片类型


# ═══════════════════════════════════════════════════════════════════════════════
# SKILL.md 草稿模板（对齐 MiMoCode compose/.bundle/new-skill/SKILL.md 的最小骨架）
# ═══════════════════════════════════════════════════════════════════════════════

_SKILL_DRAFT_TEMPLATE = """\
---
name: {name}
description: {description}
---

# {title}

> **DISTILL DRAFT** — 由 agenote_distill 自动生成于 {date}。
> **这是候选草稿，不是正式 skill**。人工 review + 填充正文后，
> move 到 `~/.config/agents/skills/{name}/SKILL.md` 才生效。
> **正文（何时用、怎么做、避坑）由人工填写**，distill 只做骨架。

## 触发场景

（人工填写：什么情况下应该用这个 skill）

## 源卡片（{card_count} 张）

{card_list}

## 相关技术栈

`{tech}`

## 步骤

（人工填写：从源卡片提炼的稳定步骤）

## 避坑

（人工填写：从源卡片的"难点与坑点"节提炼）
"""


@dataclass
class DistillCandidate:
    """一个 distill 聚类出的候选 skill（未落盘，待 review）。"""

    name: str  # 候选 skill 名（kebab-case，来自 category+tech）
    title: str  # 人类可读标题
    category: str
    tech: str
    card_count: int
    card_ids: list[str]  # 源卡片 id 列表（溯源）
    card_titles: list[str]  # 源卡片标题（供 review 判断）
    draft_path: str  # 落盘后的 draft 路径（dry_run 时为空）


@dataclass
class DistillReport:
    """一次 distill 运行报告。"""

    window_days: int
    total_kb_cards: int = 0
    candidates: list[dict] = field(default_factory=list)
    drafted: int = 0  # 实际落盘的 draft 数（dry_run 时为 0）
    skipped_existing_draft: int = 0  # 因 draft 已存在而跳过
    error_details: list[str] = field(default_factory=list)
    message: str = ""

    def to_dict(self) -> dict:
        return asdict(self)


# ═══════════════════════════════════════════════════════════════════════════════
# 辅助
# ═══════════════════════════════════════════════════════════════════════════════


def _cluster_key(card: dict) -> tuple[str, str]:
    """聚类键：(category, tech)。tech 缺失时回退 category。"""
    cat = (card.get("category") or "general").strip() or "general"
    tech = (card.get("tech") or cat).strip() or cat
    return (cat, tech)


def _to_skill_name(category: str, tech: str) -> str:
    """把 category+tech 转 kebab-case skill 名。"""
    raw = f"{tech}-{category}" if tech != category else category
    # 保留 CJK + ASCII 字母数字，其余转 -
    name = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff]+", "-", raw).strip("-").lower()
    return name or "unnamed-skill"


def _existing_draft_names() -> set[str]:
    """已落盘的 draft 名集合（幂等：避免重复生成）。"""
    names: set[str] = set()
    if not DISTILL_DIR.exists():
        return names
    for f in DISTILL_DIR.glob("*.md"):
        # 文件名格式：<date>-<name>-draft.md，取中间 name
        m = re.match(r"\d{8}-(.+)-draft\.md$", f.name)
        if m:
            names.add(m.group(1))
    return names


def _render_draft(candidate: DistillCandidate, cards: list[dict]) -> str:
    """渲染 SKILL.md 草稿（模板填空，正文留空由人工填）。"""
    card_list_items = []
    for c in cards:
        cid = c.get("id", "?")
        ctitle = c.get("title", "?")
        ctype = c.get("type", "?")
        usage = c.get("usage_count", 0)
        card_list_items.append(f"- `{cid}` ({ctype}, usage={usage}) — {ctitle}")
    # description：从聚类维度生成一句话（不杜撰步骤）
    tech = candidate.tech or candidate.category
    description = (
        f"distill 候选：{tech} 相关的 {candidate.card_count} 张经验卡片聚类的"
        f"工作流模式（需人工填充触发条件与步骤）"
    )
    return _SKILL_DRAFT_TEMPLATE.format(
        name=candidate.name,
        title=candidate.title,
        description=description,
        date=datetime.now().strftime("%Y-%m-%d"),
        card_count=candidate.card_count,
        card_list="\n".join(card_list_items) or "(无)",
        tech=tech,
    )


# ═══════════════════════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════════════════════


def _gather_candidates(cards: list[dict]) -> list[tuple[DistillCandidate, list[dict]]]:
    """从 KB 卡片聚类候选。

    入选条件（任一）：
    - type == ascended（多轮试错验证）
    - usage_count >= MIN_USAGE_FOR_ASCEND（反复使用）

    同 (category, tech) 的入选卡片 ≥ MIN_CLUSTER_SIZE 才成候选。
    """
    # 先筛入选卡片
    eligible: list[dict] = []
    for c in cards:
        if c.get("type") == ASCENDED_TYPE:
            eligible.append(c)
            continue
        try:
            if int(c.get("usage_count", 0) or 0) >= MIN_USAGE_FOR_ASCEND:
                eligible.append(c)
        except (ValueError, TypeError):
            pass

    # 按 (category, tech) 聚类
    clusters: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for c in eligible:
        clusters[_cluster_key(c)].append(c)

    candidates: list[tuple[DistillCandidate, list[dict]]] = []
    for (cat, tech), group in clusters.items():
        if len(group) < MIN_CLUSTER_SIZE:
            continue
        name = _to_skill_name(cat, tech)
        # 按创建时间排序，取标题作为候选标题
        group.sort(key=lambda c: c.get("created", ""), reverse=True)
        cand = DistillCandidate(
            name=name,
            title=f"{tech} 工作流（{cat}）",
            category=cat,
            tech=tech,
            card_count=len(group),
            card_ids=[c.get("id", "") for c in group],
            card_titles=[c.get("title", "") for c in group],
            draft_path="",
        )
        candidates.append((cand, group))

    candidates.sort(key=lambda x: x[0].card_count, reverse=True)
    return candidates


def run_distill(window_days: int = 30, dry_run: bool = True) -> DistillReport:
    """跑一次 distill（workflow packaging）。

    Args:
        window_days: 保留参数（当前扫全量 KB，未来可加时间窗）
        dry_run: True（默认）只返回候选不落盘；False 才写 draft 到 .distill/

    Returns:
        DistillReport。**零候选是合法返回**（message 说明"无待 distill 工作流"）。
    """
    report = DistillReport(window_days=window_days)
    ctx = agenote_context()
    index = _load_index(ctx)
    cards = index.get("cards", [])
    report.total_kb_cards = len(cards)

    if not cards:
        report.message = "KB 为空，无待 distill 工作流（零产物即成功）"
        return report

    raw_candidates = _gather_candidates(cards)

    if not raw_candidates:
        report.message = (
            "无候选：KB 中没有 ≥%d 张同主题的 ascended/高频卡片（零产物即成功）"
            % MIN_CLUSTER_SIZE
        )
        return report

    existing = _existing_draft_names()
    skipped = 0
    final: list[tuple[DistillCandidate, list[dict]]] = []
    for cand, group in raw_candidates:
        if cand.name in existing:
            skipped += 1
            continue
        final.append((cand, group))
    report.skipped_existing_draft = skipped

    if not final and skipped:
        report.message = (
            "全部候选已有 draft（%d 个），未生成新 draft（幂等跳过）" % skipped
        )
        # 仍把候选信息放进 report 供查看
        report.candidates = [
            {**asdict(c), "cards_in_group": len(g)} for c, g in raw_candidates
        ]
        return report

    report.candidates = [{**asdict(c), "cards_in_group": len(g)} for c, g in final]

    if dry_run:
        report.message = (
            "dry_run：%d 个候选 skill，review 后用 dry_run=False 生成 draft"
            % len(final)
        )
        return report

    # ── dry_run=False：落盘 draft 到 .distill/ ────────────────────────────
    DISTILL_DIR.mkdir(parents=True, exist_ok=True)
    date_tag = datetime.now().strftime("%Y%m%d")
    drafted = 0
    for cand, group in final:
        try:
            content = _render_draft(cand, group)
            path = DISTILL_DIR / f"{date_tag}-{cand.name}-draft.md"
            cand.draft_path = str(path)
            path.write_text(content, encoding="utf-8")
            drafted += 1
        except Exception as e:
            report.error_details.append(f"draft '{cand.name}' 失败: {e}")
    report.drafted = drafted
    # 更新 report.candidates 里的 draft_path
    report.candidates = [{**asdict(c), "cards_in_group": len(g)} for c, g in final]
    report.message = (
        "drafted %d/%d 个候选到 %s（人工 review + move 到 skills/ 才生效）"
        % (
            drafted,
            len(final),
            DISTILL_DIR,
        )
    )
    return report
