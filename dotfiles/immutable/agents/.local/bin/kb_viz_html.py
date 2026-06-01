# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
"""kb_viz_html — 知识库可视化的 HTML 模板与 CSS / JS 字符串

整个模块是纯字符串：CSS、JS 子块、HTML 骨架、`generate_html` 组装函数。
前端逻辑全部以原生 vanilla JS 编写，不引入任何外部库。
"""

import json
from string import Template

# ═══════════════════════════════════════════════════════════════════════════════
# CSS — 三主题（light / dark / auto）+ 响应式 + fixed 侧栏
# ═══════════════════════════════════════════════════════════════════════════════

EMBEDDED_CSS = r"""
:root {
  --bg: #1a1b1e;
  --bg-panel: #25262b;
  --bg-card: #2c2e33;
  --bg-hover: #373a40;
  --bg-stale: #3a2a2a;
  --text: #c1c2c5;
  --text-dim: #909296;
  --text-bright: #e9ecef;
  --border: #373a40;
  --border-strong: #4a4d54;
  --accent: #5c7cfa;
  --accent-soft: #4c6ef540;
  --green: #51cf66;
  --yellow: #fcc419;
  --orange: #ff922b;
  --red: #ff6b6b;
  --cyan: #22b8cf;
  --purple: #cc5de8;
  --pink: #f06595;
  --teal: #20c997;
  --grid-line: #ffffff10;
  --shadow: rgba(0,0,0,0.4);
}
[data-theme="light"] {
  --bg: #f8f9fa; --bg-panel: #ffffff; --bg-card: #ffffff;
  --bg-hover: #e9ecef; --bg-stale: #fff5f5;
  --text: #212529; --text-dim: #6c757d; --text-bright: #000000;
  --border: #dee2e6; --border-strong: #adb5bd;
  --accent: #4263eb; --accent-soft: #4263eb20;
  --green: #2b8a3e; --yellow: #f08c00; --orange: #d9480f;
  --red: #c92a2a; --cyan: #0c8599; --purple: #862e9c;
  --pink: #c2255c; --teal: #087f5b; --grid-line: #00000010;
  --shadow: rgba(0,0,0,0.12);
}
[data-theme="auto"] {
  --bg: #f8f9fa; --bg-panel: #ffffff; --bg-card: #ffffff;
  --bg-hover: #e9ecef; --bg-stale: #fff5f5;
  --text: #212529; --text-dim: #6c757d; --text-bright: #000000;
  --border: #dee2e6; --border-strong: #adb5bd;
  --accent: #4263eb; --accent-soft: #4263eb20;
  --green: #2b8a3e; --yellow: #f08c00; --orange: #d9480f;
  --red: #c92a2a; --cyan: #0c8599; --purple: #862e9c;
  --pink: #c2255c; --teal: #087f5b; --grid-line: #00000010;
  --shadow: rgba(0,0,0,0.12);
}
@media (prefers-color-scheme: dark) {
  [data-theme="auto"] {
    --bg: #1a1b1e; --bg-panel: #25262b; --bg-card: #2c2e33;
    --bg-hover: #373a40; --bg-stale: #3a2a2a;
    --text: #c1c2c5; --text-dim: #909296; --text-bright: #e9ecef;
    --border: #373a40; --border-strong: #4a4d54;
    --accent: #5c7cfa; --accent-soft: #4c6ef540;
    --green: #51cf66; --yellow: #fcc419; --orange: #ff922b;
    --red: #ff6b6b; --cyan: #22b8cf; --purple: #cc5de8;
    --pink: #f06595; --teal: #20c997; --grid-line: #ffffff10;
    --shadow: rgba(0,0,0,0.4);
  }
}
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, "Segoe UI", "Noto Sans SC", sans-serif;
  font-size: 14px;
  line-height: 1.6;
  padding: 0 0 40px;
  overflow-x: hidden;
}
.layout {
  display: grid;
  grid-template-columns: 240px 1fr;
  max-width: 1600px;
  margin: 0 auto;
  gap: 16px;
  padding: 0 16px;
}
@media (max-width: 900px) {
  .layout { grid-template-columns: 1fr; }
}
.hero {
  position: sticky;
  top: 0;
  z-index: 50;
  background: var(--bg);
  border-bottom: 1px solid var(--border);
  padding: 16px 20px;
  margin-bottom: 12px;
  backdrop-filter: blur(8px);
}
.hero-row { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; }
.hero h1 { font-size: 22px; color: var(--text-bright); }
.hero .subtitle { color: var(--text-dim); font-size: 12px; margin-top: 2px; }
.hero-stats { display: flex; gap: 12px; margin-left: auto; }
.hero-stat {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 6px 12px;
  text-align: center;
  min-width: 72px;
}
.hero-stat .num { font-size: 20px; font-weight: 700; color: var(--accent); display: block; }
.hero-stat .label { font-size: 10px; color: var(--text-dim); text-transform: uppercase; letter-spacing: 0.5px; }
.search-wrap { position: relative; flex: 1; min-width: 200px; max-width: 360px; }
.search-wrap input {
  width: 100%;
  background: var(--bg-card);
  color: var(--text);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 6px 10px 6px 30px;
  font-size: 13px;
}
.search-wrap input:focus { outline: none; border-color: var(--accent); }
.search-wrap::before {
  content: "🔍";
  position: absolute;
  left: 9px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 12px;
  opacity: 0.6;
}
.theme-toggle { display: flex; gap: 4px; background: var(--bg-panel); border: 1px solid var(--border); border-radius: 6px; padding: 2px; }
.theme-toggle button {
  background: transparent; color: var(--text-dim); border: none; padding: 4px 10px; font-size: 11px; border-radius: 4px; cursor: pointer;
}
.theme-toggle button.active { background: var(--accent); color: white; }
.theme-toggle button:hover:not(.active) { color: var(--text-bright); }
.stale-alert {
  background: var(--bg-stale);
  border: 1px solid var(--red);
  border-radius: 6px;
  padding: 10px 14px;
  margin: 0 0 12px;
  color: var(--text-bright);
  font-size: 13px;
}
.stale-alert strong { color: var(--red); margin-right: 6px; }
.sidebar { position: sticky; top: 92px; align-self: start; max-height: calc(100vh - 100px); overflow-y: auto; padding-right: 4px; }
.sidebar h3 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.8px; color: var(--text-dim); margin: 16px 0 8px; }
.sidebar h3:first-child { margin-top: 0; }
.tree-list { list-style: none; }
.tree-list li { padding: 3px 0; font-size: 13px; cursor: pointer; color: var(--text); display: flex; justify-content: space-between; }
.tree-list li:hover { color: var(--accent); }
.tree-list li.active { color: var(--accent); font-weight: 600; }
.tree-list li .count { color: var(--text-dim); font-size: 11px; }
.facet { display: flex; flex-wrap: wrap; gap: 4px; }
.facet button {
  background: var(--bg-panel); color: var(--text); border: 1px solid var(--border);
  border-radius: 12px; padding: 2px 10px; font-size: 11px; cursor: pointer;
}
.facet button:hover { background: var(--bg-hover); }
.facet button.active { background: var(--accent); color: white; border-color: var(--accent); }
.facet button .n { opacity: 0.7; margin-left: 4px; }
.memory-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px; }
.mem-cell { background: var(--bg-panel); border: 1px solid var(--border); border-radius: 4px; padding: 6px; text-align: center; }
.mem-cell .num { display: block; font-size: 18px; font-weight: 700; color: var(--teal); }
.mem-cell .lbl { font-size: 10px; color: var(--text-dim); }
.chart-card {
  background: var(--bg-panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 14px;
  margin-bottom: 14px;
}
.chart-card h3 { font-size: 14px; color: var(--text-bright); margin: 0 0 10px; }
.charts-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; margin-bottom: 14px; }
.charts-3 { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 14px; margin-bottom: 14px; }
@media (max-width: 1200px) { .charts-3 { grid-template-columns: 1fr 1fr; } }
@media (max-width: 700px)  { .charts-2, .charts-3 { grid-template-columns: 1fr; } }
.chart-card svg { display: block; width: 100%; }
#graph-svg { height: 480px; background: var(--bg); border-radius: 6px; }
@media (max-width: 700px) { #graph-svg { height: 340px; } }
@media (max-width: 700px) {
  .hero-row { flex-direction: column; align-items: stretch; gap: 10px; }
  .hero-stats { margin-left: 0; display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 8px; max-width: 100%; min-width: 0; }
  .search-wrap { max-width: 100%; min-width: 0; }
  .theme-toggle { align-self: flex-end; }
  .hero-stat { min-width: 0; padding: 6px 8px; }
  html, body { overflow-x: hidden; }
}
@media (max-width: 380px) {
  .hero-stats { grid-template-columns: 1fr; }
}
.graph-tooltip {
  position: absolute; display: none; background: var(--bg-card);
  border: 1px solid var(--border); border-radius: 6px; padding: 8px 10px;
  font-size: 12px; pointer-events: none; z-index: 200; max-width: 260px;
  box-shadow: 0 4px 14px var(--shadow); color: var(--text);
}
.graph-tooltip .tt-title { color: var(--text-bright); font-weight: 600; }
.graph-tooltip .tt-meta { color: var(--text-dim); margin-top: 2px; font-size: 11px; }
.detail-pane {
  position: fixed; top: 0; right: -380px; width: 360px; height: 100vh;
  background: var(--bg-panel); border-left: 1px solid var(--border);
  box-shadow: -4px 0 20px var(--shadow);
  transition: right 0.3s ease;
  z-index: 100; overflow-y: auto; padding: 20px;
}
.detail-pane.is-open { right: 0; }
.detail-pane .close {
  position: absolute; top: 10px; right: 14px; background: transparent;
  border: none; color: var(--text-dim); font-size: 22px; cursor: pointer;
}
.detail-pane h2 { font-size: 16px; color: var(--text-bright); margin: 0 30px 12px 0; line-height: 1.4; }
.detail-pane .field { margin: 8px 0; font-size: 12px; }
.detail-pane .field .k { color: var(--text-dim); margin-right: 6px; }
.detail-pane .field .v { color: var(--text); }
.detail-pane .tag { display: inline-block; background: var(--bg-card); border: 1px solid var(--border); border-radius: 10px; padding: 1px 8px; font-size: 11px; margin: 2px 2px; color: var(--text); }
.detail-pane a { color: var(--accent); text-decoration: none; }
.detail-pane a:hover { text-decoration: underline; }
.detail-pane .id-line { color: var(--text-dim); font-size: 11px; font-family: monospace; }
.detail-pane .stale-warn { background: var(--bg-stale); border: 1px solid var(--red); border-radius: 4px; padding: 6px 8px; color: var(--red); font-size: 11px; margin-top: 8px; }
.status-badge { display: inline-block; font-size: 10px; padding: 1px 6px; border-radius: 3px; font-weight: 600; }
.status-stable { background: #2b8a3e20; color: var(--green); }
.status-done { background: #1971c220; color: var(--cyan); }
.status-draft { background: #e6770020; color: var(--orange); }
.status-archived { background: #5f3dc420; color: var(--purple); }
.status-stale { background: #c92a2a20; color: var(--red); }
.card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 8px; }
@media (max-width: 500px) { .card-grid { grid-template-columns: 1fr; } }
.card-item {
  background: var(--bg-card); border: 1px solid var(--border); border-radius: 6px;
  padding: 10px 12px; cursor: pointer; transition: background 0.15s, transform 0.1s;
}
.card-item:hover { background: var(--bg-hover); }
.card-item.highlight { border-color: var(--accent); box-shadow: 0 0 0 2px var(--accent-soft); }
.card-item .title { font-size: 13px; color: var(--text-bright); display: block; margin-bottom: 4px; line-height: 1.4; }
.card-item .meta { font-size: 11px; color: var(--text-dim); display: flex; gap: 6px; flex-wrap: wrap; align-items: center; }
.card-item mark { background: var(--yellow); color: #000; padding: 0 2px; border-radius: 2px; }
.empty-state { color: var(--text-dim); padding: 24px; text-align: center; font-size: 13px; }
.count-line { color: var(--text-dim); font-size: 12px; margin-bottom: 8px; }
"""


# ═══════════════════════════════════════════════════════════════════════════════
# JS — Core (state, init, helpers)
# ═══════════════════════════════════════════════════════════════════════════════

JS_CORE = r"""
// ── 全局状态 ──
var STATE = {
  filter: {},          // {category: "guix", status: "stable"}
  search: "",
  selectedCategory: null,
  selectedId: null,
  topTechs: [],
};

function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
function debounce(fn, ms) {
  var t = null;
  return function() {
    var args = arguments, self = this;
    clearTimeout(t);
    t = setTimeout(function() { fn.apply(self, args); }, ms);
  };
}
function highlight(text, q) {
  if (!q) return esc(text);
  var idx = String(text).toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) return esc(text);
  return esc(text.slice(0, idx)) + "<mark>" + esc(text.slice(idx, idx + q.length)) + "</mark>" + esc(text.slice(idx + q.length));
}
function cardMatchSearch(c, q) {
  if (!q) return true;
  var hay = (c.title + " " + (c.tags || []).join(" ") + " " + (c.owner || "") + " " + (c.tech || "") + " " + c.id).toLowerCase();
  return hay.indexOf(q.toLowerCase()) >= 0;
}
function cardMatchFilter(c, f) {
  if (!f) return true;
  for (var k in f) {
    if (!f.hasOwnProperty(k)) continue;
    var v = f[k];
    if (!v) continue;
    if (k === "tech") {
      var parts = (c.tech || "").split(",").map(function(t) { return t.trim(); });
      if (parts.indexOf(v) < 0) return false;
    } else if (k === "entry_type") {
      if ((c.entry_type || "none") !== v) return false;
    } else {
      if ((c[k] || "") !== v) return false;
    }
  }
  return true;
}

var CARDS = window.__INIT_CARDS__ || [];
var STATS = window.__INIT_STATS__ || {};
var TOP_TECHS = window.__INIT_TOP_TECHS__ || [];

function getVisibleCards() {
  return CARDS.filter(function(c) {
    return cardMatchFilter(c, STATE.filter) && cardMatchSearch(c, STATE.search);
  });
}

function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  try { localStorage.setItem("kb-viz-theme", theme); } catch (e) {}
  var btns = document.querySelectorAll(".theme-toggle button");
  btns.forEach(function(b) { b.classList.toggle("active", b.dataset.theme === theme); });
}

var onSearch = debounce(function(val) {
  STATE.search = val.trim();
  renderAll();
}, 300);

function openDetail(id) {
  var c = CARDS.find(function(x) { return x.id === id; });
  if (!c) return;
  STATE.selectedId = id;
  var staleDays = (function() {
    if (!c.last_used) return -1;
    var d = new Date(c.last_used);
    if (isNaN(d.getTime())) return -1;
    return (Date.now() - d.getTime()) / 86400000;
  })();
  var html =
    '<button class="close" aria-label="关闭">×</button>' +
    '<h2>' + esc(c.title) + '</h2>' +
    '<div class="id-line">' + esc(c.id) + ' · ' + esc(c.file || "") + '</div>' +
    '<div class="field"><span class="k">状态</span><span class="status-badge status-' + esc(c.status || "done") + '">' + esc(c.status || "?") + '</span></div>' +
    '<div class="field"><span class="k">类别</span><span class="v">' + esc(c.category || "—") + '</span></div>' +
    '<div class="field"><span class="k">类型</span><span class="v">' + esc(c.type || "—") + '</span></div>' +
    '<div class="field"><span class="k">作者</span><span class="v">' + esc(c.owner || "—") + '</span></div>' +
    '<div class="field"><span class="k">创建</span><span class="v">' + esc(c.created || "—") + '</span></div>' +
    '<div class="field"><span class="k">最近使用</span><span class="v">' + esc(c.last_used || "—") + '</span></div>' +
    '<div class="field"><span class="k">最近验证</span><span class="v">' + esc(c.last_verified || "—") + '</span></div>' +
    '<div class="field"><span class="k">tech</span><span class="v">' + esc(c.tech || "—") + '</span></div>' +
    '<div class="field"><span class="k">entry_type</span><span class="v">' + esc(c.entry_type || "—") + '</span></div>' +
    '<div class="field"><span class="k">tags</span>' + (c.tags || []).map(function(t) { return '<span class="tag">' + esc(t) + '</span>'; }).join("") + '</div>' +
    (staleDays > 180 ? '<div class="stale-warn">⚠ 已超过 180 天未使用</div>' :
     staleDays > 60 ? '<div class="stale-warn">⚠ 已超过 60 天未使用</div>' : "");
  var pane = document.getElementById("detail-pane");
  pane.innerHTML = html;
  pane.classList.add("is-open");
  document.querySelectorAll(".card-item").forEach(function(el) {
    el.classList.toggle("highlight", el.dataset.id === id);
  });
}
function closeDetail() {
  document.getElementById("detail-pane").classList.remove("is-open");
  STATE.selectedId = null;
  document.querySelectorAll(".card-item.highlight").forEach(function(el) { el.classList.remove("highlight"); });
}
document.addEventListener("keydown", function(e) {
  if (e.key === "Escape") closeDetail();
});

function renderAll() {
  renderStale();
  renderSidebar();
  renderCharts();
  renderCards();
}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# JS — Charts (stats, 6 bar charts, timeline, heatmap)
# ═══════════════════════════════════════════════════════════════════════════════

JS_CHARTS = r"""
var CATEGORY_COLORS = {
  general:"#5c7cfa", guix:"#20c997", emacs:"#cc5de8",
  "emacs-config":"#f06595", gamedev:"#ff922b", framework:"#22b8cf", other:"#909296"
};
var STATUS_COLORS = {
  stable:"#51cf66", done:"#22b8cf", draft:"#ff922b", archived:"#cc5de8", stale:"#ff6b6b"
};
var TYPE_COLORS = {
  debug:"#ff6b6b", refactor:"#f06595", research:"#22b8cf",
  workflow:"#fcc419", feature:"#51cf66", config:"#5c7cfa"
};
var OWNER_COLORS = { human:"#ff922b", ai:"#5c7cfa", collaborative:"#20c997" };
var ENTRY_COLORS = { mistake:"#ff6b6b", note:"#5c7cfa", ascended:"#20c997" };

function countBy(cards, key, opts) {
  opts = opts || {};
  var out = {};
  cards.forEach(function(c) {
    var v = c[key];
    if (v == null || v === "") {
      if (opts.skipNull) return;
      v = "—";
    }
    if (key === "tech") {
      String(v).split(",").forEach(function(t) {
        t = t.trim(); if (t) out[t] = (out[t] || 0) + 1;
      });
    } else if (key === "entry_type") {
      v = v || "none";
      out[v] = (out[v] || 0) + 1;
    } else {
      out[v] = (out[v] || 0) + 1;
    }
  });
  return out;
}

function renderStale() {
  var bar = document.getElementById("stale-alert");
  var s60 = STATS.stale_60_count || 0, s180 = STATS.stale_180_count || 0;
  if (s60 === 0 && s180 === 0) { bar.style.display = "none"; return; }
  bar.style.display = "block";
  bar.innerHTML =
    '<strong>⚠ 陈旧卡片</strong>' +
    '60 天以上未使用: ' + s60 + ' 张 · ' +
    '180 天以上未使用: ' + s180 + ' 张（建议验证或归档）';
}

function renderSidebar() {
  var tree = countBy(CARDS, "category");
  var treeHtml = '<ul class="tree-list">';
  var cats = Object.keys(tree).sort();
  if (STATE.selectedCategory === null) {
    treeHtml += '<li class="active" data-cat=""><span>全部</span><span class="count">' + CARDS.length + '</span></li>';
  } else {
    treeHtml += '<li data-cat=""><span>全部</span><span class="count">' + CARDS.length + '</span></li>';
  }
  cats.forEach(function(k) {
    var active = (STATE.selectedCategory === k) ? " active" : "";
    treeHtml += '<li class="' + active + '" data-cat="' + esc(k) + '"><span>' + esc(k) + '</span><span class="count">' + tree[k] + '</span></li>';
  });
  treeHtml += "</ul>";
  document.getElementById("tree-list").innerHTML = treeHtml;
  document.querySelectorAll("#tree-list li").forEach(function(li) {
    li.addEventListener("click", function() {
      var v = li.dataset.cat;
      STATE.selectedCategory = v || null;
      if (v) STATE.filter.category = v;
      else delete STATE.filter.category;
      renderAll();
    });
  });

  var facetFields = [
    { key: "status", title: "状态", colorMap: STATUS_COLORS },
    { key: "type", title: "类型", colorMap: TYPE_COLORS },
    { key: "owner", title: "作者", colorMap: OWNER_COLORS },
    { key: "entry_type", title: "条目类型", colorMap: ENTRY_COLORS },
    { key: "tech", title: "技术栈 (Top 8)", colorMap: null, top: 8 },
  ];
  var html = "";
  facetFields.forEach(function(f) {
    var data = (f.key === "tech") ? topTechMap() : countBy(CARDS, f.key, { skipNull: true });
    var keys = Object.keys(data).sort(function(a, b) { return data[b] - data[a]; });
    if (f.top) keys = keys.slice(0, f.top);
    html += '<h3>' + esc(f.title) + '</h3><div class="facet">';
    keys.forEach(function(k) {
      var active = STATE.filter[f.key] === k ? " active" : "";
      var colorDot = f.colorMap && f.colorMap[k] ? ' style="border-color:' + f.colorMap[k] + '"' : "";
      html += '<button class="' + active + '" data-facet="' + esc(f.key) + '" data-val="' + esc(k) + '"' + colorDot + '>' + esc(k) + '<span class="n">' + data[k] + '</span></button>';
    });
    html += "</div>";
  });
  html += '<h3>操作</h3><div class="facet"><button data-action="reset">重置全部过滤</button></div>';
  document.getElementById("facets").innerHTML = html;
  document.querySelectorAll("#facets button[data-facet]").forEach(function(b) {
    b.addEventListener("click", function() {
      var k = b.dataset.facet, v = b.dataset.val;
      if (STATE.filter[k] === v) delete STATE.filter[k];
      else STATE.filter[k] = v;
      if (k === "category") STATE.selectedCategory = (v || null);
      renderAll();
    });
  });
  document.querySelectorAll('#facets button[data-action="reset"]').forEach(function(b) {
    b.addEventListener("click", function() {
      STATE.filter = {}; STATE.search = ""; STATE.selectedCategory = null;
      var si = document.getElementById("search-input"); if (si) si.value = "";
      renderAll();
    });
  });

  var m = STATS.memory || {};
  document.getElementById("memory-grid").innerHTML =
    '<div class="mem-cell"><span class="num">' + (m.total_feedback||0) + '</span><span class="lbl">反馈</span></div>' +
    '<div class="mem-cell"><span class="num">' + (m.total_project||0) + '</span><span class="lbl">项目</span></div>' +
    '<div class="mem-cell"><span class="num">' + (m.total_reference||0) + '</span><span class="lbl">参考</span></div>';
}

function topTechMap() {
  var out = {};
  TOP_TECHS.forEach(function(t) { out[t[0]] = t[1]; });
  return out;
}

function renderCharts() {
  var visible = getVisibleCards();
  renderBarChart("chart-category", countBy(visible, "category"), CATEGORY_COLORS, 160);
  renderBarChart("chart-type", countBy(visible, "type"), TYPE_COLORS, 160);
  renderBarChart("chart-owner", countBy(visible, "owner"), OWNER_COLORS, 160);
  renderBarChart("chart-tech", countBy(visible, "tech"), null, 200);
  renderBarChart("chart-entry", countBy(visible, "entry_type", { skipNull: true }), ENTRY_COLORS, 160);
  renderBarChart("chart-status", countBy(visible, "status"), STATUS_COLORS, 160);
  renderTimeline(visible);
  renderHeatmap(visible);
  renderForceGraph(visible);
}

function renderBarChart(svgId, data, colors, defaultH) {
  var svg = document.getElementById(svgId);
  if (!svg) return;
  var w = svg.clientWidth || 360;
  var pad = { l: 90, r: 50, t: 8, b: 8 };
  var entries = Object.entries(data).sort(function(a, b) { return b[1] - a[1]; });
  if (entries.length === 0) {
    svg.setAttribute("height", 60);
    svg.innerHTML = '<text x="' + (w/2) + '" y="35" fill="var(--text-dim)" font-size="11" text-anchor="middle">暂无数据</text>';
    return;
  }
  var max = entries[0][1];
  var barH = Math.max(10, Math.min(20, (defaultH - pad.t - pad.b) / entries.length));
  var chartW = w - pad.l - pad.r;
  var y = pad.t;
  var html = "";
  entries.forEach(function(e) {
    var name = e[0], count = e[1];
    var barW = (count / max) * chartW;
    var color = (colors && colors[name]) ? colors[name] : "var(--accent)";
    html +=
      '<text x="' + (pad.l - 6) + '" y="' + (y + barH/2 + 4) + '" fill="var(--text)" font-size="11" text-anchor="end">' + esc(name) + '</text>' +
      '<rect x="' + pad.l + '" y="' + y + '" width="' + Math.max(barW, 2) + '" height="' + (barH - 3) + '" fill="' + color + '" rx="2" opacity="0.85"/>' +
      '<text x="' + (pad.l + Math.max(barW, 2) + 4) + '" y="' + (y + barH/2 + 4) + '" fill="var(--text-dim)" font-size="11">' + count + '</text>';
    y += barH;
  });
  svg.setAttribute("height", Math.max(80, entries.length * barH + pad.t + pad.b));
  svg.innerHTML = html;
}

function renderTimeline(visible) {
  var svg = document.getElementById("chart-timeline");
  if (!svg) return;
  var w = svg.clientWidth || 720;
  var h = 240;
  var pad = { l: 50, r: 50, t: 20, b: 30 };
  function byMonth(cards, key) {
    var m = {};
    cards.forEach(function(c) {
      var d = c[key];
      if (d && d.length >= 7) {
        var ym = d.substring(0, 7);
        m[ym] = (m[ym] || 0) + 1;
      }
    });
    return m;
  }
  var created = byMonth(visible, "created");
  var used = byMonth(visible, "last_used");
  var verified = byMonth(visible, "last_verified");
  var keys = Array.from(new Set([].concat(
    Object.keys(created), Object.keys(used), Object.keys(verified)
  ))).sort();
  if (keys.length === 0) {
    svg.setAttribute("viewBox", "0 0 " + w + " " + h);
    svg.innerHTML = '<text x="' + (w/2) + '" y="' + (h/2) + '" fill="var(--text-dim)" font-size="13" text-anchor="middle">暂无时间数据</text>';
    return;
  }
  function vals(map) { return keys.map(function(k) { return map[k] || 0; }); }
  var vC = vals(created), vU = vals(used), vV = vals(verified);
  var maxLeft = Math.max.apply(null, vC) || 1;
  var maxRight = Math.max.apply(null, vU.concat(vV)) || 1;
  var chartW = w - pad.l - pad.r;
  var chartH = h - pad.t - pad.b;
  function xAt(i) { return pad.l + (keys.length === 1 ? chartW/2 : i * chartW / (keys.length - 1)); }
  function yLeft(v) { return pad.t + chartH - (v / maxLeft) * chartH; }
  function yRight(v) { return pad.t + chartH - (v / maxRight) * chartH; }
  function path(vals, yFn) {
    return vals.map(function(v, i) { return (i === 0 ? "M" : "L") + xAt(i).toFixed(1) + "," + yFn(v).toFixed(1); }).join(" ");
  }
  var html = "";
  for (var g = 0; g <= 4; g++) {
    var yy = pad.t + (g / 4) * chartH;
    html += '<line x1="' + pad.l + '" y1="' + yy + '" x2="' + (w - pad.r) + '" y2="' + yy + '" stroke="var(--grid-line)" stroke-width="1"/>';
  }
  html += '<path d="' + path(vC, yLeft) + '" stroke="var(--green)" fill="none" stroke-width="2"/>';
  html += '<path d="' + path(vU, yRight) + '" stroke="var(--cyan)" fill="none" stroke-width="2" stroke-dasharray="4 2"/>';
  html += '<path d="' + path(vV, yRight) + '" stroke="var(--orange)" fill="none" stroke-width="2" stroke-dasharray="2 2"/>';
  [vC, vU, vV].forEach(function(vals, idx) {
    var colors = ["var(--green)", "var(--cyan)", "var(--orange)"];
    vals.forEach(function(v, i) {
      if (v > 0) {
        var yy = (idx === 0) ? yLeft(v) : yRight(v);
        html += '<circle cx="' + xAt(i) + '" cy="' + yy + '" r="2.5" fill="' + colors[idx] + '"/>';
      }
    });
  });
  keys.forEach(function(k, i) {
    if (keys.length > 12 && i % Math.ceil(keys.length / 8) !== 0 && i !== keys.length - 1) return;
    html += '<text x="' + xAt(i) + '" y="' + (h - 10) + '" fill="var(--text-dim)" font-size="9" text-anchor="middle">' + esc(k) + '</text>';
  });
  for (var g2 = 0; g2 <= 4; g2++) {
    var vl = Math.round((g2 / 4) * maxLeft);
    var vr = Math.round((g2 / 4) * maxRight);
    var yy2 = pad.t + chartH - (g2 / 4) * chartH;
    html += '<text x="' + (pad.l - 6) + '" y="' + (yy2 + 3) + '" fill="var(--green)" font-size="9" text-anchor="end">' + vl + '</text>';
    html += '<text x="' + (w - pad.r + 6) + '" y="' + (yy2 + 3) + '" fill="var(--cyan)" font-size="9">' + vr + '</text>';
  }
  html +=
    '<g transform="translate(' + (w/2 - 90) + ',4)">' +
    '<rect x="0" y="0" width="10" height="3" fill="var(--green)"/><text x="14" y="5" fill="var(--text)" font-size="10">created</text>' +
    '<rect x="70" y="0" width="10" height="3" fill="var(--cyan)"/><text x="84" y="5" fill="var(--text)" font-size="10">used</text>' +
    '<rect x="130" y="0" width="10" height="3" fill="var(--orange)"/><text x="144" y="5" fill="var(--text)" font-size="10">verified</text>' +
    '</g>';
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.innerHTML = html;
}

function renderHeatmap(visible) {
  var svg = document.getElementById("chart-heatmap");
  if (!svg) return;
  var counts = {};
  visible.forEach(function(c) {
    String(c.tech || "").split(",").forEach(function(t) {
      t = t.trim();
      if (t) counts[t] = (counts[t] || 0) + 1;
    });
  });
  var techs = Object.keys(counts).filter(function(t) { return counts[t] >= 2; });
  techs.sort(function(a, b) { return counts[b] - counts[a]; });
  var rows = Math.min(8, techs.length);
  if (rows === 0) {
    svg.setAttribute("viewBox", "0 0 600 60");
    svg.innerHTML = '<text x="300" y="35" fill="var(--text-dim)" font-size="13" text-anchor="middle">暂无技术栈热力数据（频次 ≥ 2 的 tech 不足）</text>';
    return;
  }
  techs = techs.slice(0, rows);
  var now = new Date();
  var months = [];
  for (var i = 11; i >= 0; i--) {
    var d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0"));
  }
  var grid = {};
  visible.forEach(function(c) {
    String(c.tech || "").split(",").forEach(function(t) {
      t = t.trim();
      if (!t) return;
      ["created", "last_used"].forEach(function(field) {
        var d = c[field];
        if (d && d.length >= 7) {
          var ym = d.substring(0, 7);
          if (months.indexOf(ym) >= 0) {
            grid[t + "|" + ym] = (grid[t + "|" + ym] || 0) + 1;
          }
        }
      });
    });
  });
  var maxV = 0;
  Object.keys(grid).forEach(function(k) { if (grid[k] > maxV) maxV = grid[k]; });
  var labelW = 100, cellW = 36, cellH = 20, padT = 30;
  var w = labelW + months.length * cellW + 20;
  var h = padT + rows * cellH + 20;
  var html = "";
  months.forEach(function(m, i) {
    html += '<text x="' + (labelW + i * cellW + cellW/2) + '" y="20" fill="var(--text-dim)" font-size="9" text-anchor="middle">' + esc(m.substring(5)) + '</text>';
  });
  techs.forEach(function(t, ri) {
    var yy = padT + ri * cellH;
    html += '<text x="' + (labelW - 6) + '" y="' + (yy + cellH/2 + 3) + '" fill="var(--text)" font-size="10" text-anchor="end">' + esc(t) + '</text>';
    months.forEach(function(m, ci) {
      var v = grid[t + "|" + m] || 0;
      var intensity = maxV > 0 ? v / maxV : 0;
      var color = v === 0 ? "var(--bg-card)" :
        "rgba(92, 124, 250, " + (0.2 + intensity * 0.8).toFixed(2) + ")";
      html += '<rect x="' + (labelW + ci * cellW + 1) + '" y="' + (yy + 1) + '" width="' + (cellW - 2) + '" height="' + (cellH - 2) + '" fill="' + color + '" rx="2"/>';
      if (v > 0) {
        html += '<text x="' + (labelW + ci * cellW + cellW/2) + '" y="' + (yy + cellH/2 + 3) + '" fill="var(--text-bright)" font-size="9" text-anchor="middle">' + v + '</text>';
      }
    });
  });
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.innerHTML = html;
}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# JS — Force-directed (Eades 简化版)
# ═══════════════════════════════════════════════════════════════════════════════

JS_FORCE = r"""
var FORCE = {
  REPULSION:  8000,
  GRAVITY:    0.04,
  SPRING_K:   0.05,
  SPRING_L:   80,
  DAMPING:    0.85,
  ITERATIONS: 200,
  ALPHA_INIT: 1.0,
  ALPHA_MIN:  0.1,
};

function renderForceGraph(visible) {
  var svg = document.getElementById("graph-svg");
  if (!svg) return;
  var tagCount = {}, tagCards = {};
  visible.forEach(function(c) {
    (c.tags || []).forEach(function(t) {
      if (!t) return;
      if (/^(debug|workflow|research|refactor|feature|config)$/i.test(t)) return;
      if (/^(general|guix|emacs|framework|gamedev|emacs-config)$/i.test(t)) return;
      if (t === c.owner) return;
      if (t === c.category) return;
      tagCount[t] = (tagCount[t] || 0) + 1;
      if (!tagCards[t]) tagCards[t] = [];
      tagCards[t].push(c);
    });
  });
  var tags = Object.keys(tagCount).sort(function(a, b) { return tagCount[b] - tagCount[a]; });
  var topN = Math.min(tags.length, 30);
  tags = tags.slice(0, topN);
  if (tags.length === 0) {
    svg.innerHTML = '<text x="50%" y="50%" fill="var(--text-dim)" font-size="13" text-anchor="middle">暂无标签数据</text>';
    return;
  }
  var maxCount = tagCount[tags[0]];
  var cooc = {};
  visible.forEach(function(c) {
    var t = (c.tags || []).filter(function(x) { return tagCount[x]; });
    for (var i = 0; i < t.length; i++) {
      for (var j = i + 1; j < t.length; j++) {
        var key = [t[i], t[j]].sort().join("::");
        cooc[key] = (cooc[key] || 0) + 1;
      }
    }
  });
  var w = svg.clientWidth || 800;
  var h = parseInt(getComputedStyle(svg).height) || 480;
  var cx = w / 2, cy = h / 2;
  var nodes = tags.map(function(t, i) {
    var angle = (i / tags.length) * 2 * Math.PI;
    var size = 6 + (tagCount[t] / maxCount) * 14;
    return {
      tag: t, count: tagCount[t], size: size,
      x: cx + (Math.min(cx, cy) - 60) * Math.cos(angle),
      y: cy + (Math.min(cx, cy) - 60) * Math.sin(angle),
      vx: 0, vy: 0, fixed: false,
    };
  });
  var nodeMap = {};
  nodes.forEach(function(n) { nodeMap[n.tag] = n; });
  var edges = [];
  Object.keys(cooc).forEach(function(key) {
    var parts = key.split("::");
    var a = nodeMap[parts[0]], b = nodeMap[parts[1]];
    if (a && b) edges.push({ a: a, b: b, w: cooc[key] });
  });
  var alpha = FORCE.ALPHA_INIT;
  for (var iter = 0; iter < FORCE.ITERATIONS; iter++) {
    var alphaNow = Math.max(alpha, FORCE.ALPHA_MIN);
    for (var i = 0; i < nodes.length; i++) {
      var n1 = nodes[i];
      if (n1.fixed) continue;
      for (var j = 0; j < nodes.length; j++) {
        if (i === j) continue;
        var n2 = nodes[j];
        var dx = n1.x - n2.x, dy = n1.y - n2.y;
        var d2 = dx * dx + dy * dy;
        if (d2 < 1) d2 = 1;
        var f = FORCE.REPULSION / d2;
        n1.vx += (dx / Math.sqrt(d2)) * f * alphaNow;
        n1.vy += (dy / Math.sqrt(d2)) * f * alphaNow;
      }
    }
    edges.forEach(function(e) {
      var dx = e.b.x - e.a.x, dy = e.b.y - e.a.y;
      var d = Math.sqrt(dx * dx + dy * dy) || 1;
      var f = FORCE.SPRING_K * (d - FORCE.SPRING_L) * Math.min(e.w / 5, 1);
      if (!e.a.fixed) { e.a.vx += (dx / d) * f; e.a.vy += (dy / d) * f; }
      if (!e.b.fixed) { e.b.vx -= (dx / d) * f; e.b.vy -= (dy / d) * f; }
    });
    nodes.forEach(function(n) {
      if (n.fixed) return;
      n.vx += (cx - n.x) * FORCE.GRAVITY;
      n.vy += (cy - n.y) * FORCE.GRAVITY;
    });
    nodes.forEach(function(n) {
      if (n.fixed) return;
      n.vx *= FORCE.DAMPING;
      n.vy *= FORCE.DAMPING;
      n.x += n.vx;
      n.y += n.vy;
      n.x = Math.max(n.size + 2, Math.min(w - n.size - 2, n.x));
      n.y = Math.max(n.size + 2, Math.min(h - n.size - 2, n.y));
    });
    alpha *= 0.97;
  }
  var html = "";
  edges.forEach(function(e) {
    var op = Math.min(0.15 + e.w * 0.06, 0.5);
    html += '<line x1="' + e.a.x.toFixed(1) + '" y1="' + e.a.y.toFixed(1) + '" x2="' + e.b.x.toFixed(1) + '" y2="' + e.b.y.toFixed(1) + '" stroke="var(--accent)" stroke-width="' + Math.min(e.w, 3) + '" opacity="' + op.toFixed(2) + '"/>';
  });
  nodes.forEach(function(n) {
    var cat = (tagCards[n.tag] && tagCards[n.tag][0]) ? (tagCards[n.tag][0].category || "other") : "other";
    var color = CATEGORY_COLORS[cat] || "var(--accent)";
    html += '<g class="gnode" data-tag="' + esc(n.tag) + '" style="cursor:pointer">';
    html += '<circle cx="' + n.x.toFixed(1) + '" cy="' + n.y.toFixed(1) + '" r="' + n.size + '" fill="' + color + '" opacity="0.9" stroke="var(--bg)" stroke-width="1.5"/>';
    html += '<text x="' + n.x.toFixed(1) + '" y="' + (n.y + n.size + 11).toFixed(1) + '" fill="var(--text-dim)" font-size="10" text-anchor="middle">' + esc(n.tag) + ' (' + n.count + ')</text>';
    html += '</g>';
  });
  svg.innerHTML = html;
  svg.setAttribute("width", w);
  svg.setAttribute("height", h);
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.style.maxWidth = "100%";
  svg.style.height = "auto";
  var tt = document.getElementById("graph-tooltip");
  svg.querySelectorAll(".gnode").forEach(function(g) {
    g.addEventListener("mouseenter", function(e) {
      var tag = g.dataset.tag;
      var list = (tagCards[tag] || []).slice(0, 5);
      var html2 = '<div class="tt-title">' + esc(tag) + '</div><div class="tt-meta">出现 ' + tagCount[tag] + ' 次</div>';
      list.forEach(function(c) { html2 += '<div class="tt-meta">· ' + esc(c.title.substring(0, 50)) + '</div>'; });
      if ((tagCards[tag] || []).length > 5) html2 += '<div class="tt-meta">… 还有 ' + ((tagCards[tag] || []).length - 5) + ' 张</div>';
      tt.innerHTML = html2;
      tt.style.display = "block";
    });
    g.addEventListener("mousemove", function(e) {
      tt.style.left = Math.min(e.clientX + 12, window.innerWidth - 280) + "px";
      tt.style.top = (e.clientY + 12) + "px";
    });
    g.addEventListener("mouseleave", function() { tt.style.display = "none"; });
  });
}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# JS — 卡片网格 + 搜索联动
# ═══════════════════════════════════════════════════════════════════════════════

JS_INTERACT = r"""
function renderCards() {
  var visible = getVisibleCards();
  var q = STATE.search;
  var container = document.getElementById("card-list");
  document.getElementById("count-line").textContent =
    "显示 " + visible.length + " / " + CARDS.length + " 张卡片" +
    (Object.keys(STATE.filter).length || q ? "（已过滤）" : "");
  if (visible.length === 0) {
    container.innerHTML = '<div class="empty-state">没有匹配的卡片</div>';
    return;
  }
  var html = "";
  visible.forEach(function(c) {
    var stCls = "status-" + (c.status || "done");
    var catColor = CATEGORY_COLORS[c.category || "other"] || "var(--accent)";
    html +=
      '<div class="card-item" data-id="' + esc(c.id) + '">' +
      '  <span class="title">' + highlight(c.title || "untitled", q) + '</span>' +
      '  <div class="meta">' +
      '    <span class="status-badge ' + stCls + '">' + esc(c.status || "?") + '</span>' +
      '    <span style="color:' + catColor + '">' + esc(c.category || "") + '</span>' +
      '    <span>' + esc(c.type || "") + '</span>' +
      '    <span>👤 ' + esc(c.owner || "") + '</span>' +
      '    <span>' + esc(c.created || "") + '</span>' +
      '  </div>' +
      '</div>';
  });
  container.innerHTML = html;
  container.querySelectorAll(".card-item").forEach(function(el) {
    el.addEventListener("click", function() { openDetail(el.dataset.id); });
  });
  if (STATE.selectedId) {
    var sel = container.querySelector('[data-id="' + STATE.selectedId + '"]');
    if (sel) sel.classList.add("highlight");
  }
}

function renderHeroStats() {
  var el = document.getElementById("hero-stats");
  el.innerHTML =
    '<div class="hero-stat"><span class="num">' + (STATS.total || 0) + '</span><span class="label">总卡片</span></div>' +
    '<div class="hero-stat"><span class="num">' + (STATS.stale_60_count || 0) + '</span><span class="label">60d+</span></div>' +
    '<div class="hero-stat"><span class="num">' + (STATS.stale_180_count || 0) + '</span><span class="label">180d+</span></div>' +
    '<div class="hero-stat"><span class="num">' + ((STATS.memory && STATS.memory.total_feedback) || 0) + '</span><span class="label">反馈记忆</span></div>';
}

function init() {
  CARDS = window.__INIT_CARDS__ || [];
  STATS = window.__INIT_STATS__ || {};
  TOP_TECHS = window.__INIT_TOP_TECHS__ || [];
  STATE.filter = window.__INIT_FILTER__ || {};
  STATE.search = window.__INIT_SEARCH__ || "";

  var saved = null;
  try { saved = localStorage.getItem("kb-viz-theme"); } catch (e) {}
  applyTheme(saved || window.__INIT_THEME__ || "auto");
  document.querySelectorAll(".theme-toggle button").forEach(function(b) {
    b.addEventListener("click", function() { applyTheme(b.dataset.theme); });
  });

  var si = document.getElementById("search-input");
  si.value = STATE.search;
  si.addEventListener("input", function() { onSearch(si.value); });

  var dp = document.getElementById("detail-pane");
  dp.addEventListener("click", function(e) {
    if (e.target.classList && e.target.classList.contains("close")) closeDetail();
  });

  renderHeroStats();
  renderAll();
  var resizeT = null;
  window.addEventListener("resize", function() {
    clearTimeout(resizeT);
    resizeT = setTimeout(renderCharts, 200);
  });
}
"""


# ═══════════════════════════════════════════════════════════════════════════════
# HTML 骨架模板（string.Template，命名占位）
# ═══════════════════════════════════════════════════════════════════════════════

HTML_TEMPLATE = r"""<!DOCTYPE html>
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
      <h1>📊 知识库可视化</h1>
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
      <h3>🔗 标签力导向图（共现关系 · Eades 简化算法）</h3>
      <div style="position:relative">
        <svg id="graph-svg"></svg>
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
      <h3>📈 时间线（双 Y 轴：左 created · 右 used/verified）</h3>
      <svg id="chart-timeline" preserveAspectRatio="xMidYMid meet"></svg>
    </div>

    <div class="chart-card">
      <h3>🔥 月度热力图（top tech × 最近 12 个月 · 动态行数）</h3>
      <svg id="chart-heatmap" preserveAspectRatio="xMinYMin meet"></svg>
    </div>

    <div class="chart-card">
      <h3>📋 卡片</h3>
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
"""


# ═══════════════════════════════════════════════════════════════════════════════
# 组装函数
# ═══════════════════════════════════════════════════════════════════════════════


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
    tmpl = Template(HTML_TEMPLATE)
    return tmpl.substitute(
        theme=theme,
        css=EMBEDDED_CSS,
        total=stats.get("total", 0),
        updated=updated,
        cards_json=_json_safe(cards),
        stats_json=_json_safe(stats),
        top_techs_json=_json_safe(top_techs),
        filter_json=_json_safe(init_filter),
        search_json=_json_safe(init_search),
        theme_json=_json_safe(theme),
        js_core=JS_CORE,
        js_charts=JS_CHARTS,
        js_force=JS_FORCE,
        js_interact=JS_INTERACT,
    )
