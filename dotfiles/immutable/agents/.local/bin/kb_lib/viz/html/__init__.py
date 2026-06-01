# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz_html — 知识库可视化的 HTML 组装入口。

CSS / JS / HTML 模板分别存放在本子包内:
- style.css    三主题样式表
- core.js      状态、详情面板、搜索防抖
- charts.js    6 张分布图、时间线、热力图
- force.js     力导向图（Eades 简化算法 + 平滑缩放）
- interact.js  卡片渲染 + init
- template.py  HTML 骨架（string.Template 命名占位）

本模块负责在运行时把这些文件读出并内联到单一 HTML 字符串中。
"""
import json
from pathlib import Path

from .template import HTML_TEMPLATE
from kb_lib.viz.data import attach_card_bodies


def _read(name: str) -> str:
    return (Path(__file__).parent / name).read_text(encoding="utf-8")


def _json_safe(obj) -> str:
    """把 obj 序列化为可嵌入 <script> 的 JSON 字符串。"""
    return (
        json.dumps(obj, ensure_ascii=False)
        .replace("</script", "<\\/script")
        .replace("<!--", "<\\!--")
    )


def generate_html(
    *,
    updated: str,
    cards: list[dict],
    stats: dict,
    top_techs: list[tuple[str, int]],
    theme: str,
    init_filter: dict,
    init_search: str,
) -> str:
    """组装 HTML 字符串。"""
    cards_with_body = attach_card_bodies(cards)
    return HTML_TEMPLATE.substitute(
        theme=theme,
        css=_read("style.css"),
        total=stats.get("total", 0),
        updated=updated,
        cards_json=_json_safe(cards_with_body),
        stats_json=_json_safe(stats),
        top_techs_json=_json_safe(top_techs),
        filter_json=_json_safe(init_filter),
        search_json=_json_safe(init_search),
        theme_json=_json_safe(theme),
        js_core=_read("core.js"),
        js_charts=_read("charts.js"),
        js_force=_read("force.js"),
        js_interact=_read("interact.js"),
    )
