// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT
function renderCards() {
  var visible = getVisibleCards();
  var q = STATE.search;
  var container = document.getElementById("card-list");
  document.getElementById("count-line").textContent =
    "显示 " +
    visible.length +
    " / " +
    CARDS.length +
    " 张卡片" +
    (Object.keys(STATE.filter).length || q ? "（已过滤）" : "");
  if (visible.length === 0) {
    container.innerHTML = '<div class="empty-state">没有匹配的卡片</div>';
    return;
  }
  var html = "";
  visible.forEach(function (c) {
    var stCls = "status-" + (c.status || "done");
    var catColor = CATEGORY_COLORS[c.category || "other"] || "var(--accent)";
    html +=
      '<div class="card-item" data-id="' +
      esc(c.id) +
      '">' +
      '  <span class="title">' +
      highlight(c.title || "untitled", q) +
      "</span>" +
      '  <div class="meta">' +
      '    <span class="status-badge ' +
      stCls +
      '">' +
      esc(c.status || "?") +
      "</span>" +
      '    <span style="color:' +
      catColor +
      '">' +
      esc(c.category || "") +
      "</span>" +
      "    <span>" +
      esc(c.type || "") +
      "</span>" +
      "    <span>👤 " +
      esc(c.owner || "") +
      "</span>" +
      "    <span>" +
      esc(c.created || "") +
      "</span>" +
      "  </div>" +
      "</div>";
  });
  container.innerHTML = html;
  container.querySelectorAll(".card-item").forEach(function (el) {
    el.addEventListener("click", function () {
      openDetail(el.dataset.id);
    });
  });
  if (STATE.selectedId) {
    var sel = container.querySelector('[data-id="' + STATE.selectedId + '"]');
    if (sel) sel.classList.add("highlight");
  }
}

function renderHeroStats() {
  var el = document.getElementById("hero-stats");
  el.innerHTML =
    '<div class="hero-stat"><span class="num">' +
    (STATS.total || 0) +
    '</span><span class="label">总卡片</span></div>' +
    '<div class="hero-stat"><span class="num">' +
    (STATS.stale_60_count || 0) +
    '</span><span class="label">60d+</span></div>' +
    '<div class="hero-stat"><span class="num">' +
    (STATS.stale_180_count || 0) +
    '</span><span class="label">180d+</span></div>' +
    '<div class="hero-stat"><span class="num">' +
    ((STATS.memory && STATS.memory.total_feedback) || 0) +
    '</span><span class="label">反馈记忆</span></div>';
}

function init() {
  CARDS = window.__INIT_CARDS__ || [];
  STATS = window.__INIT_STATS__ || {};
  TOP_TECHS = window.__INIT_TOP_TECHS__ || [];
  STATE.filter = window.__INIT_FILTER__ || {};
  STATE.search = window.__INIT_SEARCH__ || "";

  var saved = null;
  try {
    saved = localStorage.getItem("kb-viz-theme");
  } catch (e) {}
  applyTheme(saved || window.__INIT_THEME__ || "auto");
  document.querySelectorAll(".theme-toggle button").forEach(function (b) {
    b.addEventListener("click", function () {
      applyTheme(b.dataset.theme);
    });
  });

  var si = document.getElementById("search-input");
  si.value = STATE.search;
  si.addEventListener("input", function () {
    onSearch(si.value);
  });

  var dp = document.getElementById("detail-pane");
  dp.addEventListener("click", function (e) {
    if (e.target.classList && e.target.classList.contains("close"))
      closeDetail();
  });

  renderHeroStats();
  renderAll();
  var resizeT = null;
  window.addEventListener("resize", function () {
    clearTimeout(resizeT);
    resizeT = setTimeout(renderCharts, 200);
  });
}
