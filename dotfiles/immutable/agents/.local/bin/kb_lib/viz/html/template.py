# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""HTML 模板 — string.Template 命名占位。"""

from string import Template

HTML_TEMPLATE = Template(r"""<!DOCTYPE html>
<html lang="zh-CN" data-theme="${theme}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>知识库可视化 — kb-viz</title>
<style>${css}</style>
</head>
<body>

<header class="hero">
  <div class="hero-row">
    <div>
      <h1>知识库可视化</h1>
      <div class="subtitle">共 ${total} 张卡片 · 最后更新 ${updated}</div>
    </div>
    <div class="search-wrap">
      <input type="text" id="search-input" placeholder="搜索标题、标签、作者、tech、ID…">
    </div>
    <div class="theme-toggle" role="tablist" aria-label="主题">
      <button data-theme="light">亮</button>
      <button data-theme="dark">暗</button>
      <button data-theme="auto">自动</button>
    </div>
    <div class="hero-stats" id="hero-stats"></div>
  </div>
</header>

<div id="stale-alert" class="stale-alert" style="display:none"></div>

<div class="layout">

  <aside class="sidebar">
    <h3>类别</h3>
    <div id="tree-list"></div>
    <h3>多维过滤</h3>
    <div id="facets"></div>
    <h3>记忆概览</h3>
    <div id="memory-grid" class="memory-grid"></div>
  </aside>

  <main>

    <div class="chart-card">
      <h3>标签力导向图</h3>
      <div style="position:relative">
        <svg id="graph-svg"></svg>
        <div class="graph-controls">
          <button data-zoom="in" title="放大">+</button>
          <button data-zoom="out" title="缩小">−</button>
          <button data-zoom="reset" title="重置">⟳</button>
        </div>
        <div class="graph-tooltip" id="graph-tooltip"></div>
      </div>
    </div>

    <div class="charts-3">
      <div class="chart-card"><h3>类别分布</h3><svg id="chart-category" height="160"></svg></div>
      <div class="chart-card"><h3>类型分布</h3><svg id="chart-type" height="160"></svg></div>
      <div class="chart-card"><h3>作者分布</h3><svg id="chart-owner" height="160"></svg></div>
    </div>

    <div class="charts-3">
      <div class="chart-card"><h3>技术栈</h3><svg id="chart-tech" height="200"></svg></div>
      <div class="chart-card"><h3>条目类型</h3><svg id="chart-entry" height="160"></svg></div>
      <div class="chart-card"><h3>状态</h3><svg id="chart-status" height="160"></svg></div>
    </div>

    <div class="chart-card">
      <h3>时间线（双 Y 轴：左 created · 右 used/verified）</h3>
      <svg id="chart-timeline" preserveAspectRatio="xMidYMid meet"></svg>
    </div>

    <div class="chart-card">
      <h3>月度热力图（top tech × 最近 12 个月 · 动态行数）</h3>
      <svg id="chart-heatmap" preserveAspectRatio="xMinYMin meet"></svg>
    </div>

    <div class="chart-card">
      <h3>卡片</h3>
      <div class="count-line" id="count-line"></div>
      <div class="card-grid" id="card-list"></div>
    </div>

  </main>
</div>

<aside id="detail-pane" class="detail-pane" aria-label="卡片详情"></aside>

<script>
window.__INIT_CARDS__ = ${cards_json};
window.__INIT_STATS__ = ${stats_json};
window.__INIT_TOP_TECHS__ = ${top_techs_json};
window.__INIT_FILTER__ = ${filter_json};
window.__INIT_SEARCH__ = ${search_json};
window.__INIT_THEME__ = ${theme_json};
</script>
<script>${js_core}</script>
<script>${js_charts}</script>
<script>${js_force}</script>
<script>${js_interact}</script>
<script>document.addEventListener("DOMContentLoaded", init);</script>
</body>
</html>
""")
