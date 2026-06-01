#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz — 知识库 Web 可视化生成器

读取 index.json 和 MEMORY.org，生成自包含 HTML 页面（纯 CSS + Vanilla JS + SVG）。
"""

import json
import re
import subprocess
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

from kb_core import KB_ROOT, KB_INDEX, KB_MEMORY, _load_index


def _memory_overview() -> dict:
    """解析 MEMORY.org，返回记忆概览数据。"""
    if not KB_MEMORY.exists():
        return {"total_feedback": 0, "total_project": 0, "total_reference": 0}

    content = KB_MEMORY.read_text(encoding="utf-8")
    feedback = len(re.findall(r"^\*\* F\d{3} ", content, re.MULTILINE))
    # 精确匹配 project 节：找 * project 和下一个 * 之间的 ** 条目数
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


def _build_category_tree(index: dict) -> list[dict]:
    """从 cards 的 file 路径构建分类树。"""
    cat_counts: dict[str, list[str]] = defaultdict(list)
    for card in index.get("cards", []):
        path = card.get("file", "unknown")
        parts = path.split("/")
        if len(parts) >= 2:
            cat_counts[parts[1]].append(card["id"])
        else:
            cat_counts["_root"].append(card["id"])

    tree = []
    for cat, ids in sorted(cat_counts.items()):
        tree.append({"name": cat, "count": len(ids), "card_ids": ids})
    return tree


def _top_tags(index: dict, limit: int = 30) -> list[tuple[str, int]]:
    """统计最常用的 tags。"""
    counter: Counter = Counter()
    for card in index.get("cards", []):
        for tag in card.get("tags", []):
            counter[tag] += 1
    return counter.most_common(limit)


def generate_html(index: dict, memory: dict, output_path: str) -> None:
    """生成自包含 HTML 并写入文件。"""
    cards_json = (
        json.dumps(index.get("cards", []), ensure_ascii=False)
        .replace("</script", "<\\/script")
        .replace("<!--", "<\\!--")
    )
    memory_json = (
        json.dumps(memory, ensure_ascii=False)
        .replace("</script", "<\\/script")
        .replace("<!--", "<\\!--")
    )
    total = index.get("total", 0)
    updated = index.get("updated", "")

    html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>知识库可视化 — kb-viz</title>
<style>
/* ── 深色主题 ────────────────────────────────────────────── */
:root {{
  --bg: #1a1b1e;
  --bg-panel: #25262b;
  --bg-card: #2c2e33;
  --bg-hover: #373a40;
  --text: #c1c2c5;
  --text-dim: #909296;
  --text-bright: #e9ecef;
  --border: #373a40;
  --accent: #5c7cfa;
  --accent-dim: #4c6ef5;
  --green: #51cf66;
  --yellow: #fcc419;
  --orange: #ff922b;
  --red: #ff6b6b;
  --cyan: #22b8cf;
  --purple: #cc5de8;
  --pink: #f06595;
  --teal: #20c997;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, "Segoe UI", "Noto Sans SC", sans-serif;
  font-size: 14px;
  line-height: 1.6;
  padding: 20px;
}}
h1 {{ font-size: 24px; color: var(--text-bright); margin-bottom: 4px; }}
.subtitle {{ color: var(--text-dim); font-size: 13px; margin-bottom: 24px; }}
h2 {{ font-size: 18px; color: var(--text-bright); margin: 24px 0 12px; }}
h3 {{ font-size: 15px; color: var(--text-bright); margin: 16px 0 8px; }}
.container {{ max-width: 1400px; margin: 0 auto; }}
/* ── 统计概览卡片 ─────────────────────────────────────────── */
.stats-grid {{
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}}
.stat-card {{
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  text-align: center;
}}
.stat-card .num {{
  font-size: 32px;
  font-weight: 700;
  color: var(--accent);
  display: block;
}}
.stat-card .label {{
  font-size: 12px;
  color: var(--text-dim);
  margin-top: 4px;
}}
/* ── 图表卡片 ─────────────────────────────────────────────── */
.chart-card {{
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
  overflow-x: auto;
}}
.chart-card h3 {{ margin: 0 0 12px; }}
.chart-card svg {{
  display: block;
  margin: 0 auto;
}}
.charts-row {{
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 16px;
}}
@media (max-width: 900px) {{
  .charts-row {{ grid-template-columns: 1fr; }}
}}
/* ── 分类树 ────────────────────────────────────────────────── */
.tree-container ul {{
  list-style: none;
  padding-left: 20px;
}}
.tree-container li {{
  position: relative;
  padding: 4px 0;
  cursor: default;
}}
.tree-container li::before {{
  content: "📁 ";
}}
.tree-container li .count {{
  color: var(--text-dim);
  font-size: 12px;
  margin-left: 6px;
}}
/* ── 筛选器 ────────────────────────────────────────────────── */
.filters {{
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 16px;
  align-items: center;
}}
.filters label {{
  font-size: 12px;
  color: var(--text-dim);
  margin-right: 4px;
}}
.filters select {{
  background: var(--bg-card);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 8px;
  font-size: 13px;
  cursor: pointer;
}}
.filters select:focus {{
  outline: none;
  border-color: var(--accent);
}}
.filters .btn-reset {{
  background: var(--bg-card);
  color: var(--text-dim);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 12px;
  font-size: 13px;
  cursor: pointer;
}}
.filters .btn-reset:hover {{
  background: var(--bg-hover);
  color: var(--text-bright);
}}
/* ── 卡片列表（筛选结果） ──────────────────────────────────── */
.card-list {{
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 8px;
}}
.card-item {{
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 10px 12px;
  transition: background 0.15s;
}}
.card-item:hover {{
  background: var(--bg-hover);
}}
.card-item .title {{
  font-size: 13px;
  color: var(--text-bright);
  display: block;
  margin-bottom: 4px;
  line-height: 1.4;
}}
.card-item .meta {{
  font-size: 11px;
  color: var(--text-dim);
}}
.card-item .meta span {{
  display: inline-block;
  margin-right: 8px;
}}
.status-badge {{
  display: inline-block;
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 3px;
  font-weight: 600;
}}
.status-stable {{ background: #2b8a3e20; color: var(--green); }}
.status-done {{ background: #1971c220; color: var(--cyan); }}
.status-draft {{ background: #e6770020; color: var(--orange); }}
.status-archived {{ background: #5f3dc420; color: var(--purple); }}
.status-stale {{ background: #c92a2a20; color: var(--red); }}
/* ── 知识图谱 SVG ──────────────────────────────────────────── */
#graph-svg {{
  width: 100%;
  height: 500px;
  background: transparent;
}}
.graph-tooltip {{
  position: absolute;
  display: none;
  background: var(--bg-card);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 8px 12px;
  font-size: 12px;
  pointer-events: none;
  z-index: 100;
  max-width: 250px;
  box-shadow: 0 4px 12px rgba(0,0,0,0.4);
}}
.graph-tooltip .tt-title {{ color: var(--text-bright); font-weight: 600; }}
.graph-tooltip .tt-meta {{ color: var(--text-dim); margin-top: 2px; }}
/* ── 响应式 ────────────────────────────────────────────────── */
@media (max-width: 600px) {{
  body {{ padding: 12px; }}
  .stats-grid {{ grid-template-columns: repeat(2, 1fr); }}
  .card-list {{ grid-template-columns: 1fr; }}
  #graph-svg {{ height: 350px; }}
}}
</style>
</head>
<body>
<div class="container">
<h1>📊 知识库可视化</h1>
<p class="subtitle">共 {total} 张卡片 · 最后更新 {updated}</p>

<!-- ═══ 统计概览 ═══ -->
<div class="stats-grid" id="stats-grid"></div>

<!-- ═══ 分布图 ═══ -->
<div class="charts-row">
  <div class="chart-card">
    <h3>按类别分布 (Category)</h3>
    <svg id="chart-category" width="100%" height="220"></svg>
  </div>
  <div class="chart-card">
    <h3>按类型分布 (Type)</h3>
    <svg id="chart-type" width="100%" height="220"></svg>
  </div>
</div>
<div class="charts-row">
  <div class="chart-card">
    <h3>按状态分布 (Status)</h3>
    <svg id="chart-status" width="100%" height="220"></svg>
  </div>
  <div class="chart-card">
    <h3>时间线</h3>
    <svg id="chart-timeline" width="100%" height="220"></svg>
  </div>
</div>

<!-- ═══ 知识图谱 ═══ -->
<div class="chart-card">
  <h3>🔗 标签关系图</h3>
  <div style="position:relative">
    <svg id="graph-svg"></svg>
    <div class="graph-tooltip" id="graph-tooltip"></div>
  </div>
</div>

<!-- ═══ 分类树 + 筛选器 ═══ -->
<div class="charts-row">
  <div class="chart-card">
    <h3>📂 分类树</h3>
    <div class="tree-container" id="tree-container"></div>
  </div>
  <div class="chart-card">
    <h3>记忆概览</h3>
    <div id="memory-summary"></div>
  </div>
</div>

<!-- ═══ 卡片浏览 ═══ -->
<div class="chart-card">
  <h3>📋 卡片浏览</h3>
  <div class="filters" id="filters"></div>
  <div class="card-list" id="card-list"></div>
</div>

</div>

<script>
// ═══════════════════════════════════════════════════════════════════
// 数据
// ═══════════════════════════════════════════════════════════════════
var CARDS = {cards_json};
var MEMORY = {memory_json};
var CATEGORY_COLORS = {{
  "general": "#5c7cfa", "guix": "#20c997", "emacs": "#cc5de8",
  "emacs-config": "#f06595", "gamedev": "#ff922b", "framework": "#22b8cf",
  "other": "#909296"
}};

// ═══════════════════════════════════════════════════════════════════
// 统计概览
// ═══════════════════════════════════════════════════════════════════
function renderStats() {{
  var statusCounts = {{}}, catCounts = {{}}, typeCounts = {{}};
  CARDS.forEach(function(c) {{
    statusCounts[c.status || "unknown"] = (statusCounts[c.status || "unknown"] || 0) + 1;
    catCounts[c.category || "other"] = (catCounts[c.category || "other"] || 0) + 1;
    typeCounts[c.type || "other"] = (typeCounts[c.type || "other"] || 0) + 1;
  }});
  var grid = document.getElementById("stats-grid");
  grid.innerHTML =
    '<div class="stat-card"><span class="num">' + CARDS.length + '</span><span class="label">总卡片数</span></div>' +
    '<div class="stat-card"><span class="num">' + Object.keys(statusCounts).length + '</span><span class="label">状态数</span></div>' +
    '<div class="stat-card"><span class="num">' + Object.keys(catCounts).length + '</span><span class="label">类别数</span></div>' +
    '<div class="stat-card"><span class="num">' + Object.keys(typeCounts).length + '</span><span class="label">类型数</span></div>' +
    '<div class="stat-card"><span class="num">' + (MEMORY.total_feedback || 0) + '</span><span class="label">反馈记忆</span></div>' +
    '<div class="stat-card"><span class="num">' + (MEMORY.total_project || 0) + '</span><span class="label">项目记忆</span></div>';
}}

// ═══════════════════════════════════════════════════════════════════
// 柱状图（水平条）
// ═══════════════════════════════════════════════════════════════════
function renderBarChart(svgId, data, colors, labelKey) {{
  var svg = document.getElementById(svgId);
  var w = svg.clientWidth || 500;
  var h = 220;
  var pad = {{l: 90, r: 30, t: 20, b: 30}};
  var bars = Object.entries(data).sort(function(a,b) {{ return b[1] - a[1]; }});
  var total = bars.reduce(function(s, e) {{ return s + e[1]; }}, 0);
  var max = bars.length ? bars[0][1] : 1;
  var barH = Math.min(28, (h - pad.t - pad.b) / Math.max(bars.length, 1));
  var chartW = w - pad.l - pad.r;
  var y = pad.t;

  svg.innerHTML = '<rect x="0" y="0" width="' + w + '" height="' + h + '" fill="transparent"/>';
  bars.forEach(function(b) {{
    var name = b[0], count = b[1];
    var barW = (count / max) * chartW;
    var color = getColor(name, colors);
    var pct = total > 0 ? (count / total * 100).toFixed(1) : 0;
    svg.innerHTML +=
      '<text x="' + (pad.l - 6) + '" y="' + (y + barH/2 + 4) + '" fill="var(--text)" font-size="11" text-anchor="end">' + esc(name) + '</text>' +
      '<rect x="' + pad.l + '" y="' + y + '" width="' + Math.max(barW, 2) + '" height="' + (barH - 4) + '" fill="' + color + '" rx="3" opacity="0.85"/>' +
      '<text x="' + (pad.l + Math.max(barW, 2) + 4) + '" y="' + (y + barH/2 + 4) + '" fill="var(--text-dim)" font-size="11">' + count + ' (' + pct + '%)</text>';
    y += barH;
  }});
}}

function getColor(name, colors) {{
  return colors[name] || (typeof colors === "function" ? colors(name) : "var(--accent)");
}}
function esc(s) {{ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }}

// ═══════════════════════════════════════════════════════════════════
// 状态颜色
// ═══════════════════════════════════════════════════════════════════
var STATUS_COLORS = {{
  "stable": "#51cf66", "done": "#22b8cf", "draft": "#ff922b",
  "archived": "#cc5de8", "stale": "#ff6b6b"
}};
var TYPE_COLORS = function(t) {{
  var m = {{"debug":"#ff6b6b","refactor":"#f06595","research":"#22b8cf","workflow":"#fcc419","feature":"#51cf66","config":"#5c7cfa"}};
  return m[t] || "var(--text-dim)";
}};

// ═══════════════════════════════════════════════════════════════════
// 时间线
// ═══════════════════════════════════════════════════════════════════
function renderTimeline(svgId) {{
  var svg = document.getElementById(svgId);
  var w = svg.clientWidth || 500;
  var h = 220;
  var pad = {{l: 50, r: 20, t: 20, b: 30}};

  var months = {{}};
  CARDS.forEach(function(c) {{
    var d = c.created || "";
    if (d.length >= 7) {{
      var m = d.substring(0, 7);
      months[m] = (months[m] || 0) + 1;
    }}
  }});
  var keys = Object.keys(months).sort();
  if (keys.length === 0) {{ svg.innerHTML = '<text x="' + (w/2) + '" y="' + (h/2) + '" fill="var(--text-dim)" font-size="13" text-anchor="middle">暂无时间数据</text>'; return; }}

  var max = Math.max.apply(null, keys.map(function(k) {{ return months[k]; }}));
  var chartW = w - pad.l - pad.r;
  var chartH = h - pad.t - pad.b;
  var barW = Math.max(8, Math.min(40, chartW / keys.length - 2));

  svg.innerHTML = '<rect x="0" y="0" width="' + w + '" height="' + h + '" fill="transparent"/>';
  keys.forEach(function(k, i) {{
    var count = months[k];
    var barH = (count / max) * chartH;
    var x = pad.l + i * (barW + 2);
    var y = pad.t + chartH - barH;
    svg.innerHTML +=
      '<rect x="' + x + '" y="' + y + '" width="' + barW + '" height="' + barH + '" fill="var(--accent)" rx="2" opacity="0.8"/>' +
      '<text x="' + (x + barW/2) + '" y="' + (pad.t + chartH + 14) + '" fill="var(--text-dim)" font-size="9" text-anchor="middle">' + k + '</text>' +
      '<text x="' + (x + barW/2) + '" y="' + (y - 4) + '" fill="var(--text)" font-size="10" text-anchor="middle">' + count + '</text>';
  }});
}}

// ═══════════════════════════════════════════════════════════════════
// 知识图谱（力导向布局简化版 — 圆形排列 + 连接线）
// ═══════════════════════════════════════════════════════════════════
function renderGraph(svgId) {{
  var svg = document.getElementById(svgId);
  var w = svg.clientWidth || 800;
  var h = 500;
  var cx = w / 2, cy = h / 2;
  svg.innerHTML = '';

  // 统计 tag 频次
  var tagCount = {{}};
  var tagCards = {{}};  // tag -> [card]
  CARDS.forEach(function(c) {{
    (c.tags || []).forEach(function(t) {{
      tagCount[t] = (tagCount[t] || 0) + 1;
      if (!tagCards[t]) tagCards[t] = [];
      tagCards[t].push(c);
    }});
  }});

  var tags = Object.keys(tagCount).sort(function(a,b) {{ return tagCount[b] - tagCount[a]; }});
  if (tags.length === 0) {{
    svg.innerHTML = '<text x="' + cx + '" y="' + cy + '" fill="var(--text-dim)" font-size="13" text-anchor="middle">暂无标签数据</text>';
    return;
  }}

  // 只取 top 30 避免过密
  var topN = Math.min(tags.length, 30);
  tags = tags.slice(0, topN);
  var maxCount = tagCount[tags[0]];

  // 计算 tag co-occurrence（两两连接）
  var cooc = {{}};
  CARDS.forEach(function(c) {{
    var t = c.tags || [];
    for (var i = 0; i < t.length; i++) {{
      for (var j = i+1; j < t.length; j++) {{
        var key = [t[i], t[j]].sort().join("::");
        cooc[key] = (cooc[key] || 0) + 1;
      }}
    }}
  }});

  // 圆形排列
  var radius = Math.min(cx, cy) - 50;
  var nodes = tags.map(function(tag, i) {{
    var angle = (i / tags.length) * 2 * Math.PI - Math.PI / 2;
    var size = 5 + (tagCount[tag] / maxCount) * 15;
    var cat = tagCards[tag][0] ? tagCards[tag][0].category || "other" : "other";
    var color = CATEGORY_COLORS[cat] || "var(--accent)";
    return {{
      tag: tag,
      count: tagCount[tag],
      x: cx + radius * Math.cos(angle),
      y: cy + radius * Math.sin(angle),
      size: size,
      color: color,
      cat: cat
    }};
  }});

  // 建立节点索引
  var nodeMap = {{}};
  nodes.forEach(function(n) {{ nodeMap[n.tag] = n; }});

  // 画连接线（只画 co-occurrence >= 2 的强关联）
  var edges = [];
  Object.keys(cooc).forEach(function(key) {{
    var parts = key.split("::");
    var a = nodeMap[parts[0]], b = nodeMap[parts[1]];
    if (a && b && cooc[key] >= 2) {{
      edges.push({{a: a, b: b, weight: cooc[key]}});
    }}
  }});

  // 绘制连接线（先画线在节点下面）
  edges.forEach(function(e) {{
    var opacity = Math.min(0.1 + e.weight * 0.05, 0.4);
    var line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", e.a.x); line.setAttribute("y1", e.a.y);
    line.setAttribute("x2", e.b.x); line.setAttribute("y2", e.b.y);
    line.setAttribute("stroke", "var(--accent)");
    line.setAttribute("stroke-width", Math.min(e.weight, 4));
    line.setAttribute("opacity", opacity);
    svg.appendChild(line);
  }});

  // 绘制节点（分组：circle + text）
  nodes.forEach(function(n) {{
    var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    g.style.cursor = "pointer";
    var circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("cx", n.x); circle.setAttribute("cy", n.y);
    circle.setAttribute("r", n.size);
    circle.setAttribute("fill", n.color);
    circle.setAttribute("opacity", "0.85");
    circle.setAttribute("stroke", "rgba(255,255,255,0.1)");
    circle.setAttribute("stroke-width", "1");
    g.appendChild(circle);

    var text = document.createElementNS("http://www.w3.org/2000/svg", "text");
    text.setAttribute("x", n.x); text.setAttribute("y", n.y + n.size + 11);
    text.setAttribute("fill", "var(--text-dim)");
    text.setAttribute("font-size", "10");
    text.setAttribute("text-anchor", "middle");
    text.textContent = n.tag + " (" + n.count + ")";
    g.appendChild(text);

    // tooltip
    g.addEventListener("mouseenter", function(e) {{
      var tt = document.getElementById("graph-tooltip");
      var cardList = (tagCards[n.tag] || []).slice(0, 5);
      var html = '<div class="tt-title">' + esc(n.tag) + '</div>' +
        '<div class="tt-meta">出现 ' + n.count + ' 次 · 类别 ' + n.cat + '</div>' +
        '<div class="tt-meta" style="margin-top:4px">相关卡片:</div>';
      cardList.forEach(function(c) {{
        html += '<div class="tt-meta">· ' + esc(c.title.substring(0, 50)) + '</div>';
      }});
      if ((tagCards[n.tag] || []).length > 5) {{
        html += '<div class="tt-meta" style="color:var(--text-dim)">… 还有 ' + ((tagCards[n.tag] || []).length - 5) + ' 张</div>';
      }}
      tt.innerHTML = html;
      tt.style.display = "block";
      tt.style.left = Math.min(e.clientX + 10, window.innerWidth - 260) + "px";
      tt.style.top = e.clientY + 10 + "px";
    }});
    g.addEventListener("mousemove", function(e) {{
      var tt = document.getElementById("graph-tooltip");
      tt.style.left = Math.min(e.clientX + 10, window.innerWidth - 260) + "px";
      tt.style.top = e.clientY + 10 + "px";
    }});
    g.addEventListener("mouseleave", function() {{
      document.getElementById("graph-tooltip").style.display = "none";
    }});
    svg.appendChild(g);
  }});
}}

// ═══════════════════════════════════════════════════════════════════
// 分类树
// ═══════════════════════════════════════════════════════════════════
function renderTree(containerId) {{
  var tree = {{}};
  CARDS.forEach(function(c) {{
    var path = (c.file || "").split("/");
    if (path.length >= 2) {{
      var cat = path[1];
      tree[cat] = (tree[cat] || 0) + 1;
    }}
  }});
  var keys = Object.keys(tree).sort();
  var html = "<ul>";
  keys.forEach(function(k) {{
    html += '<li>' + esc(k) + ' <span class="count">(' + tree[k] + ')</span></li>';
  }});
  html += "</ul>";
  document.getElementById(containerId).innerHTML = html;
}}

// ═══════════════════════════════════════════════════════════════════
// 记忆概览
// ═══════════════════════════════════════════════════════════════════
function renderMemory(containerId) {{
  var html =
    '<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px">' +
    '  <div class="stat-card"><span class="num">' + (MEMORY.total_feedback || 0) + '</span><span class="label">反馈</span></div>' +
    '  <div class="stat-card"><span class="num">' + (MEMORY.total_project || 0) + '</span><span class="label">项目</span></div>' +
    '  <div class="stat-card"><span class="num">' + (MEMORY.total_reference || 0) + '</span><span class="label">参考</span></div>' +
    '</div>';
  document.getElementById(containerId).innerHTML = html;
}}

// ═══════════════════════════════════════════════════════════════════
// 筛选器 + 卡片列表
// ═══════════════════════════════════════════════════════════════════
function buildFilters() {{
  var cats = {{}}, types = {{}}, statuses = {{}};
  CARDS.forEach(function(c) {{
    cats[c.category || "other"] = 1;
    types[c.type || "other"] = 1;
    statuses[c.status || "unknown"] = 1;
  }});
  var catOpts = Object.keys(cats).sort();
  var typeOpts = Object.keys(types).sort();
  var statusOpts = Object.keys(statuses).sort();

  var html =
    '<label>类别</label><select id="filter-cat"><option value="">全部</option>' +
    catOpts.map(function(v) {{ return '<option value="' + v + '">' + v + '</option>'; }}).join("") +
    '</select>' +
    '<label>类型</label><select id="filter-type"><option value="">全部</option>' +
    typeOpts.map(function(v) {{ return '<option value="' + v + '">' + v + '</option>'; }}).join("") +
    '</select>' +
    '<label>状态</label><select id="filter-status"><option value="">全部</option>' +
    statusOpts.map(function(v) {{ return '<option value="' + v + '">' + v + '</option>'; }}).join("") +
    '</select>' +
    '<button class="btn-reset" onclick="resetFilters()">重置</button>' +
    '<span id="filter-count" style="margin-left:auto;font-size:12px;color:var(--text-dim)"></span>';
  document.getElementById("filters").innerHTML = html;

  ["filter-cat", "filter-type", "filter-status"].forEach(function(id) {{
    document.getElementById(id).addEventListener("change", applyFilters);
  }});
  applyFilters();
}}

function applyFilters() {{
  var cat = document.getElementById("filter-cat").value;
  var type = document.getElementById("filter-type").value;
  var status = document.getElementById("filter-status").value;
  var filtered = CARDS.filter(function(c) {{
    return (!cat || c.category === cat) &&
           (!type || c.type === type) &&
           (!status || c.status === status);
  }});
  renderCardList(filtered);
  document.getElementById("filter-count").textContent = "显示 " + filtered.length + " / " + CARDS.length + " 张卡片";
}}

function resetFilters() {{
  document.getElementById("filter-cat").value = "";
  document.getElementById("filter-type").value = "";
  document.getElementById("filter-status").value = "";
  applyFilters();
}}

function renderCardList(cards) {{
  var container = document.getElementById("card-list");
  if (cards.length === 0) {{
    container.innerHTML = '<div style="color:var(--text-dim);padding:20px;text-align:center">没有匹配的卡片</div>';
    return;
  }}
  var html = "";
  cards.forEach(function(c) {{
    var stCls = "status-" + (c.status || "done");
    var catColor = CATEGORY_COLORS[c.category || "other"] || "var(--accent)";
    html +=
      '<div class="card-item">' +
      '  <span class="title">' + esc(c.title) + '</span>' +
      '  <div class="meta">' +
      '    <span class="status-badge ' + stCls + '">' + (c.status || "?") + '</span>' +
      '    <span style="color:' + catColor + '">' + esc(c.category || "") + '</span>' +
      '    <span>' + esc(c.type || "") + '</span>' +
      '    <span>' + esc(c.created || "") + '</span>' +
      '    <span>👤 ' + esc(c.owner || "") + '</span>' +
      '  </div>' +
      '</div>';
  }});
  container.innerHTML = html;
}}

// ═══════════════════════════════════════════════════════════════════
// 初始化
// ═══════════════════════════════════════════════════════════════════
function init() {{
  // 统计
  var cats = {{}}, types = {{}}, statuses = {{}};
  CARDS.forEach(function(c) {{
    var cat = c.category || "other";
    cats[cat] = (cats[cat] || 0) + 1;
    var t = c.type || "other";
    types[t] = (types[t] || 0) + 1;
    var s = c.status || "unknown";
    statuses[s] = (statuses[s] || 0) + 1;
  }});
  renderStats();
  renderBarChart("chart-category", cats, CATEGORY_COLORS);
  renderBarChart("chart-type", types, TYPE_COLORS);
  renderBarChart("chart-status", statuses, STATUS_COLORS);
  renderTimeline("chart-timeline");
  renderGraph("graph-svg");
  renderTree("tree-container");
  renderMemory("memory-summary");
  buildFilters();
}}

window.addEventListener("DOMContentLoaded", init);
window.addEventListener("resize", function() {{
  // 响应式重绘
  var cats = {{}}, types = {{}}, statuses = {{}};
  CARDS.forEach(function(c) {{
    var cat = c.category || "other"; cats[cat] = (cats[cat] || 0) + 1;
    var t = c.type || "other"; types[t] = (types[t] || 0) + 1;
    var s = c.status || "unknown"; statuses[s] = (statuses[s] || 0) + 1;
  }});
  renderBarChart("chart-category", cats, CATEGORY_COLORS);
  renderBarChart("chart-type", types, TYPE_COLORS);
  renderBarChart("chart-status", statuses, STATUS_COLORS);
  renderTimeline("chart-timeline");
  renderGraph("graph-svg");
}});
</script>
</body>
</html>"""

    Path(output_path).write_text(html, encoding="utf-8")
    print(f"✅ 可视化页面已生成: {output_path}")


def cmd_viz(args: "argparse.Namespace") -> None:
    """生成知识库可视化 HTML 页面。"""
    index = _load_index()
    if not index.get("cards"):
        print("❌ 知识库索引为空。请先运行 'kb reindex' 重建索引。")
        return

    memory = _memory_overview()
    output = args.output

    generate_html(index, memory, output)

    if args.open:
        import subprocess

        try:
            subprocess.run(["xdg-open", output], check=True)
            print("🌐 已在浏览器中打开。")
        except (FileNotFoundError, subprocess.CalledProcessError) as e:
            print(f"⚠ 无法自动打开浏览器: {e}")
