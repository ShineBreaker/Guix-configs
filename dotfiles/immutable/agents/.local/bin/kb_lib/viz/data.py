# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz_data — 知识库可视化的 Python 端数据预处理

把 index.json / MEMORY.org 转换为前端可直接消费的 dict。
所有计算与单位规整都在此模块完成，前端只负责呈现。
"""

import re
import sys
from collections import Counter
from datetime import datetime

from kb_lib.core import KB_MEMORY


# ═══════════════════════════════════════════════════════════════════════════════
# --filter 字段白名单（与索引卡片字段对齐）
# ═══════════════════════════════════════════════════════════════════════════════

KNOWN_FILTER_KEYS = {
    "category",
    "type",
    "owner",
    "tech",
    "entry_type",
    "status",
}


# ═══════════════════════════════════════════════════════════════════════════════
# 记忆概览
# ═══════════════════════════════════════════════════════════════════════════════


def memory_overview() -> dict:
    """解析 MEMORY.org，返回反馈/项目/参考记忆数。"""
    if not KB_MEMORY.exists():
        return {"total_feedback": 0, "total_project": 0, "total_reference": 0}

    content = KB_MEMORY.read_text(encoding="utf-8")
    feedback = len(re.findall(r"^\*\* F\d{3} ", content, re.MULTILINE))
    proj_section = re.search(
        r"^\* project\b.*?(?=^\* [a-z]|\Z)", content, re.MULTILINE | re.DOTALL
    )
    project = (
        len(re.findall(r"^\*\* ", proj_section.group(0), re.MULTILINE))
        if proj_section
        else 0
    )
    reference = len(re.findall(r"^\*\* R\d{3} ", content, re.MULTILINE))
    return {
        "total_feedback": feedback,
        "total_project": project,
        "total_reference": reference,
    }


# ═══════════════════════════════════════════════════════════════════════════════
# 日期 / 距离
# ═══════════════════════════════════════════════════════════════════════════════


def parse_org_date(s: str) -> str:
    """把 Org 时间戳 [2026-06-01 Mon 02:17] 规整为 ISO 日期 '2026-06-01'。

    失败或空值返回空串。
    """
    if not s:
        return ""
    m = re.search(r"(\d{4}-\d{2}-\d{2})", s)
    return m.group(1) if m else ""


def days_since(date_str: str, today: datetime | None = None) -> float:
    """计算距今天的天数。空值或解析失败返回 -1（哨兵）。"""
    if not date_str:
        return -1.0
    try:
        d = datetime.fromisoformat(date_str)
    except ValueError:
        return -1.0
    ref = today or datetime.now()
    return (ref - d).total_seconds() / 86400.0


# ═══════════════════════════════════════════════════════════════════════════════
# --filter 解析
# ═══════════════════════════════════════════════════════════════════════════════


def parse_filter(s: str) -> dict:
    """把 'cat=guix,status=stable' 解析为 dict。未知字段 stderr warning。"""
    out: dict[str, str] = {}
    if not s:
        return out
    for part in s.split(","):
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        k = k.strip()
        v = v.strip()
        if not k:
            continue
        if k not in KNOWN_FILTER_KEYS:
            print(
                f"⚠ 未知过滤字段: {k!r}（已知: {', '.join(sorted(KNOWN_FILTER_KEYS))}）",
                file=sys.stderr,
            )
            continue
        if v:
            out[k] = v
    return out


# ═══════════════════════════════════════════════════════════════════════════════
# STATS 预处理
# ═══════════════════════════════════════════════════════════════════════════════


def normalize_cards(cards: list[dict]) -> list[dict]:
    """把 last_used / last_verified 规整为 ISO 日期，前端按日期直接计算。"""
    out = []
    for c in cards:
        nc = dict(c)
        nc["last_used"] = parse_org_date(c.get("last_used", ""))
        nc["last_verified"] = parse_org_date(c.get("last_verified", ""))
        out.append(nc)
    return out


def compute_stats(cards: list[dict], memory: dict) -> dict:
    """Python 端预计算：总数、陈旧列表、记忆概览。

    陈旧判定：last_used 距今 > 60 天 或 > 180 天。空值不计入。
    """
    normalized = normalize_cards(cards)
    stale_60 = [c for c in normalized if 0 < days_since(c["last_used"]) > 60]
    stale_180 = [c for c in normalized if 0 < days_since(c["last_used"]) > 180]
    return {
        "total": len(cards),
        "memory": memory,
        "stale_60_count": len(stale_60),
        "stale_180_count": len(stale_180),
        "stale_60_ids": [c["id"] for c in stale_60],
        "stale_180_ids": [c["id"] for c in stale_180],
    }


def top_techs(cards: list[dict], limit: int = 8) -> list[tuple[str, int]]:
    """tech 字段是逗号分隔字符串，统计每个 tech 的卡片数。"""
    counter: Counter = Counter()
    for c in cards:
        for t in (c.get("tech") or "").split(","):
            t = t.strip()
            if t:
                counter[t] += 1
    return counter.most_common(limit)
