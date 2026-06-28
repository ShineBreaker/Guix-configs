# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz_data — 知识库可视化的 Python 端数据预处理

把 index.json 转换为前端可直接消费的 dict。
所有计算与单位规整都在此模块完成，前端只负责呈现。
"""

import re
import sys
from collections import Counter
from datetime import datetime

from kb_lib.core import KB_ROOT


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
# MEMORY 章节已废弃；偏好/项目上下文由 Hermes memory 工具管理
# viz 不再生成 memory_overview 数据


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


def compute_stats(cards: list[dict], memory: dict | None = None) -> dict:
    """Python 端预计算：总数、陈旧列表。

    陈旧判定：last_used 距今 > 60 天 或 > 180 天。空值不计入。
    `memory` 参数保留为可选以兼容旧调用，但不再生成相关数据。
    """
    normalized = normalize_cards(cards)
    stale_60 = [c for c in normalized if 0 < days_since(c["last_used"]) > 60]
    stale_180 = [c for c in normalized if 0 < days_since(c["last_used"]) > 180]
    return {
        "total": len(cards),
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


# ═══════════════════════════════════════════════════════════════════════════════
# Org 渲染（详情面板正文）
# ═══════════════════════════════════════════════════════════════════════════════

import html as _html

_HEADING_RE = re.compile(r"^(\*+)\s+(.*)$")
_SRC_BEGIN_RE = re.compile(r"^#\+begin_src\s+(\S+)?\s*$")
_BEGIN_RE = re.compile(r"^#\+begin_(\S+)\s*$")
_END_RE = re.compile(r"^#\+end_(\S+)\s*$")
_PROPS_BEGIN_RE = re.compile(r"^:PROPERTIES:\s*$")
_PROPS_END_RE = re.compile(r"^:END:\s*$")
_LIST_RE = re.compile(r"^\s*[+\-]\s+(.*)$")
_PROP_LINE_RE = re.compile(r"^:\S+:\s*.*$")
_DIRECTIVE_RE = re.compile(r"^#\+\S+:.*$")
_TODO_STATES = ("TODO", "DONE", "NEXT", "WAITING", "WAIT", "CANCELLED", "CANCEL")


def _inline(text: str) -> str:
    """HTML escape 后替换 ~code~ / *bold* / /italic/ / [[link][desc]]。"""
    out = _html.escape(text, quote=False)
    out = re.sub(r"~([^~\s][^~]*?)~", r"<code>\1</code>", out)
    out = re.sub(r"\*([^*\s][^*\n]*?)\*", r"<strong>\1</strong>", out)
    out = re.sub(r"/([^/\s][^/\n]*?)/", r"<em>\1</em>", out)
    out = re.sub(r"\[\[([^\]\[]+?)\]\[([^\]\[]+?)\]\]", r'<a href="\1">\2</a>', out)
    out = re.sub(r"\[\[([^\]\[]+?)\]\]", r'<a href="\1">\1</a>', out)
    return out


def render_card_body(file_relpath: str) -> str:
    """把 .org 卡片正文渲染为 HTML 片段。失败返回空串。

    跳过 PROPERTIES drawer、文件级 #+ 指令、单行 :tag:tag: 标记。
    支持:标题、列表、代码块、~code~/*bold*//italic//[[link]]。
    """
    if not file_relpath:
        return ""
    p = KB_ROOT / file_relpath
    if not p.exists() or p.suffix != ".org":
        return ""
    try:
        lines = p.read_text(encoding="utf-8").splitlines()
    except OSError:
        return ""

    out: list[str] = []
    in_props = False
    in_block = False
    block_lang = ""
    block_buf: list[str] = []
    list_buf: list[str] = []
    para_buf: list[str] = []

    def flush_para() -> None:
        if para_buf:
            text = " ".join(para_buf).strip()
            if text:
                out.append(f"<p>{_inline(text)}</p>")
            para_buf.clear()

    def flush_list() -> None:
        if list_buf:
            out.append("<ul>")
            for item in list_buf:
                out.append(f"<li>{_inline(item)}</li>")
            out.append("</ul>")
            list_buf.clear()

    def flush_block() -> None:
        if block_buf:
            escaped = _html.escape("\n".join(block_buf), quote=False)
            cls = f' class="lang-{block_lang}"' if block_lang else ""
            out.append(f"<pre><code{cls}>{escaped}</code></pre>")
            block_buf.clear()

    for line in lines:
        s = line.rstrip()

        if _PROPS_BEGIN_RE.match(s):
            in_props = True
            flush_para(); flush_list(); flush_block()
            continue
        if in_props:
            if _PROPS_END_RE.match(s):
                in_props = False
            continue

        m = _SRC_BEGIN_RE.match(s)
        if m and not in_block:
            in_block = True
            block_lang = m.group(1) or ""
            flush_para(); flush_list()
            continue
        m = _BEGIN_RE.match(s)
        if m and not in_block:
            in_block = True
            block_lang = ""
            flush_para(); flush_list()
            continue
        if _END_RE.match(s) and in_block:
            in_block = False
            flush_block()
            continue
        if in_block:
            block_buf.append(line)
            continue

        m = _HEADING_RE.match(s)
        if m:
            level = min(len(m.group(1)), 5)
            text = m.group(2)
            for state in _TODO_STATES:
                if text.startswith(state + " "):
                    text = text[len(state) + 1:]
                    break
            flush_para(); flush_list()
            out.append(f"<h{level}>{_inline(text)}</h{level}>")
            continue

        m = _LIST_RE.match(s)
        if m:
            flush_para()
            list_buf.append(m.group(1).strip())
            continue

        if _PROP_LINE_RE.match(s) or _DIRECTIVE_RE.match(s):
            continue

        if not s.strip():
            flush_para(); flush_list()
            continue

        list_buf.clear()
        para_buf.append(s.strip())

    flush_para(); flush_list(); flush_block()
    return "\n".join(out)


def attach_card_bodies(cards: list[dict]) -> list[dict]:
    """为每张卡加 body 字段（HTML 片段）。读 .org 失败时 body 为空串。"""
    out = []
    for c in cards:
        nc = dict(c)
        nc["body"] = render_card_body(c.get("file", ""))
        out.append(nc)
    return out
