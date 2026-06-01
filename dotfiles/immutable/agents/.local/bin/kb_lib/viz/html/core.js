// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT
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
    (c.body && c.body.trim()
      ? '<div class="body">' + c.body + '</div>'
      : '<div class="body body-empty">（无内容）</div>') +
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
