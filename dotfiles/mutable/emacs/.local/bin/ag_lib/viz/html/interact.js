// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

// ════════════════════════════════════════════════════════════════
// 卡片渲染
// ════════════════════════════════════════════════════════════════

function sortVisible(cards) {
  var key = STATE.sort || "default";
  if (key === "default") return cards;
  var copy = cards.slice();
  if (key === "newest") {
    copy.sort(function (a, b) {
      return (b.created || "").localeCompare(a.created || "");
    });
  } else if (key === "oldest") {
    copy.sort(function (a, b) {
      return (a.created || "").localeCompare(b.created || "");
    });
  } else if (key === "title") {
    copy.sort(function (a, b) {
      return (a.title || "").localeCompare(b.title || "", "zh-Hans-CN");
    });
  } else if (key === "staleness") {
    function days(c) {
      if (!c.last_used) return -1;
      var d = new Date(c.last_used);
      if (isNaN(d.getTime())) return -1;
      return (Date.now() - d.getTime()) / 86400000;
    }
    copy.sort(function (a, b) {
      return days(b) - days(a);
    });
  }
  return copy;
}

function renderCards() {
  var container = document.getElementById("card-list");
  var filtered = getVisibleCards();
  var sorted = sortVisible(filtered);
  var q = STATE.search;
  var hasFilter = Object.keys(STATE.filter).length > 0 || q;

  var countEl = document.getElementById("count-line");
  if (hasFilter) {
    countEl.innerHTML =
      '显示 <strong style="color:var(--text-bright)">' +
      sorted.length +
      "</strong> / " +
      CARDS.length +
      ' 张卡片<span class="filtered-mark">· 已过滤</span>';
  } else {
    countEl.innerHTML =
      '共 <strong style="color:var(--text-bright)">' +
      sorted.length +
      "</strong> 张卡片";
  }

  if (sorted.length === 0) {
    container.innerHTML =
      '<div class="empty-state">' +
      '<span class="icon">∅</span>' +
      '<span class="title">没有匹配的卡片</span>' +
      '<span class="hint">试试调整搜索关键词，或点击「重置全部过滤」</span>' +
      "</div>";
    return;
  }

  var html = "";
  sorted.forEach(function (c) {
    var stCls = "status-" + (c.status || "done");
    var cat = c.category || "other";
    var catColor = CATEGORY_COLORS[cat] || "var(--accent)";
    var owner = c.owner || "—";
    var ownerColor =
      owner === "ai"
        ? "var(--cyan)"
        : owner === "human"
          ? "var(--orange)"
          : owner === "collab"
            ? "var(--teal)"
            : "var(--text-dim)";
    var typeColor = TYPE_COLORS[c.type] || "var(--text-dim)";
    var titleHtml = highlight(c.title || "untitled", q);
    var meta = [];
    meta.push(
      '<span class="status-badge ' +
        stCls +
        '">' +
        esc(c.status || "?") +
        "</span>",
    );
    meta.push(
      '<span><i class="cat-dot" style="background:' +
        catColor +
        '"></i>' +
        esc(cat) +
        "</span>",
    );
    if (c.type) {
      meta.push(
        '<span style="color:' + typeColor + '">' + esc(c.type) + "</span>",
      );
    }
    meta.push(
      '<span style="color:' + ownerColor + '">· ' + esc(owner) + "</span>",
    );
    if (c.created) {
      meta.push("<span>· " + esc(c.created) + "</span>");
    }
    html +=
      '<div class="card-item" data-id="' +
      esc(c.id) +
      '" tabindex="0" role="button" aria-label="打开卡片：' +
      esc(c.title || c.id) +
      '">' +
      '<span class="title">' +
      titleHtml +
      "</span>" +
      '<div class="meta">' +
      meta.join("") +
      "</div>" +
      "</div>";
  });
  container.innerHTML = html;
  container.querySelectorAll(".card-item").forEach(function (el) {
    el.addEventListener("click", function () {
      openDetail(el.dataset.id);
    });
    el.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        openDetail(el.dataset.id);
      }
    });
  });
  if (STATE.selectedId) highlightSelected(STATE.selectedId);
}

function highlightSelected(id) {
  document.querySelectorAll(".card-item.highlight").forEach(function (el) {
    el.classList.remove("highlight");
  });
  var sel = document.querySelector('.card-item[data-id="' + id + '"]');
  if (sel) {
    sel.classList.add("highlight");
    sel.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }
}

// ════════════════════════════════════════════════════════════════
// 顶部统计
// ════════════════════════════════════════════════════════════════

function renderHeroStats() {
  var el = document.getElementById("hero-stats");
  var staleDays = STATS.stale_threshold_days || 30,
    archiveDays = STATS.archive_threshold_days || 90;
  el.innerHTML =
    '<div class="hero-stat" title="知识库总卡片数">' +
    '<span class="num">' +
    (STATS.total || 0) +
    '</span><span class="label">总卡片</span></div>' +
    '<div class="hero-stat" title="' +
    staleDays +
    ' 天以上未使用（stale）">' +
    '<span class="num" style="color:var(--orange)">' +
    (STATS.stale_count || 0) +
    '</span><span class="label">' +
    staleDays +
    "d+</span></div>" +
    '<div class="hero-stat" title="' +
    archiveDays +
    ' 天以上未使用（建议归档）">' +
    '<span class="num" style="color:var(--red)">' +
    (STATS.archive_count || 0) +
    '</span><span class="label">' +
    archiveDays +
    "d+</span></div>";
}

// ════════════════════════════════════════════════════════════════
// 入口
// ════════════════════════════════════════════════════════════════

function init() {
  CARDS = window.__INIT_CARDS__ || [];
  STATS = window.__INIT_STATS__ || {};
  TOP_TECHS = window.__INIT_TOP_TECHS__ || [];
  STATE.filter = window.__INIT_FILTER__ || {};
  STATE.search = window.__INIT_SEARCH__ || "";

  // 主题
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

  // 搜索
  var si = document.getElementById("search-input");
  si.value = STATE.search;
  si.addEventListener("input", function () {
    onSearch(si.value);
  });

  // 排序
  var ss = document.getElementById("sort-select");
  if (ss) {
    ss.value = STATE.sort || "default";
    ss.addEventListener("change", function () {
      STATE.sort = ss.value;
      renderCards();
    });
  }

  // 详情面板关闭
  var dp = document.getElementById("detail-pane");
  dp.addEventListener("click", function (e) {
    if (e.target.classList && e.target.classList.contains("close"))
      closeDetail();
  });
  // 详情面板导航
  dp.addEventListener("click", function (e) {
    if (e.target.closest(".detail-nav-prev")) navigateDetail(-1);
    else if (e.target.closest(".detail-nav-next")) navigateDetail(1);
  });

  // 全局快捷键
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      closeDetail();
      return;
    }
    // / 聚焦搜索框
    if (e.key === "/" && document.activeElement !== si) {
      e.preventDefault();
      si.focus();
      si.select();
      return;
    }
    // 在搜索框内按 Esc 清空
    if (e.key === "Escape" && document.activeElement === si) {
      si.value = "";
      onSearch("");
      si.blur();
      return;
    }
    // 详情面板打开时：j/k 或 ←/→ 翻页
    if (STATE.selectedId) {
      if (e.key === "j" || e.key === "ArrowDown") {
        e.preventDefault();
        navigateDetail(1);
      } else if (e.key === "k" || e.key === "ArrowUp") {
        e.preventDefault();
        navigateDetail(-1);
      }
    }
  });

  renderHeroStats();
  renderAll();

  // resize 防抖
  var resizeT = null;
  window.addEventListener("resize", function () {
    clearTimeout(resizeT);
    resizeT = setTimeout(renderCharts, 200);
  });
}
