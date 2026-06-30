// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

// ════════════════════════════════════════════════════════════════
// 全局状态
// ════════════════════════════════════════════════════════════════

var STATE = {
  filter: {}, // {category: "guix", status: "stable"}
  search: "",
  sort: "default", // default | newest | oldest | title | staleness
  selectedCategory: null,
  selectedId: null,
  topTechs: [],
};

// ════════════════════════════════════════════════════════════════
// 工具函数
// ════════════════════════════════════════════════════════════════

function esc(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function debounce(fn, ms) {
  var t = null;
  return function () {
    var args = arguments,
      self = this;
    clearTimeout(t);
    t = setTimeout(function () {
      fn.apply(self, args);
    }, ms);
  };
}

function highlight(text, q) {
  if (!q) return esc(text);
  var idx = String(text).toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) return esc(text);
  return (
    esc(text.slice(0, idx)) +
    "<mark>" +
    esc(text.slice(idx, idx + q.length)) +
    "</mark>" +
    esc(text.slice(idx + q.length))
  );
}

function cardMatchSearch(c, q) {
  if (!q) return true;
  var hay = (
    c.title +
    " " +
    (c.tags || []).join(" ") +
    " " +
    (c.owner || "") +
    " " +
    (c.tech || "") +
    " " +
    c.id
  ).toLowerCase();
  return hay.indexOf(q.toLowerCase()) >= 0;
}

function cardMatchFilter(c, f) {
  if (!f) return true;
  for (var k in f) {
    if (!f.hasOwnProperty(k)) continue;
    var v = f[k];
    if (!v) continue;
    if (k === "tech") {
      var parts = (c.tech || "").split(",").map(function (t) {
        return t.trim();
      });
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
  return CARDS.filter(function (c) {
    return cardMatchFilter(c, STATE.filter) && cardMatchSearch(c, STATE.search);
  });
}

// ════════════════════════════════════════════════════════════════
// 主题
// ════════════════════════════════════════════════════════════════

function applyTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  try {
    localStorage.setItem("kb-viz-theme", theme);
  } catch (e) {}
  var btns = document.querySelectorAll(".theme-toggle button");
  btns.forEach(function (b) {
    b.classList.toggle("active", b.dataset.theme === theme);
  });
}

// ════════════════════════════════════════════════════════════════
// 搜索
// ════════════════════════════════════════════════════════════════

var onSearch = debounce(function (val) {
  STATE.search = val.trim();
  renderAll();
}, 200);

// ════════════════════════════════════════════════════════════════
// 详情面板
// ════════════════════════════════════════════════════════════════

function getVisibleCardIds() {
  return getVisibleCards().map(function (c) {
    return c.id;
  });
}

function findAdjacentId(step) {
  // 优先使用当前可见集；否则退到全量
  var ids = getVisibleCardIds();
  if (ids.length === 0) {
    ids = CARDS.map(function (c) {
      return c.id;
    });
  }
  if (ids.length === 0) return null;
  var idx = ids.indexOf(STATE.selectedId);
  if (idx < 0) return ids[0];
  var next = idx + step;
  if (next < 0) next = ids.length - 1;
  if (next >= ids.length) next = 0;
  return ids[next];
}

function navigateDetail(step) {
  var id = findAdjacentId(step);
  if (id) openDetail(id);
}

function daysSinceDate(s) {
  if (!s) return -1;
  var d = new Date(s);
  if (isNaN(d.getTime())) return -1;
  return (Date.now() - d.getTime()) / 86400000;
}

function fieldRow(k, v) {
  if (v == null || v === "") return "";
  return (
    '<div class="field"><span class="k">' +
    esc(k) +
    '</span><span class="v">' +
    esc(String(v)) +
    "</span></div>"
  );
}

function openDetail(id) {
  var c = CARDS.find(function (x) {
    return x.id === id;
  });
  if (!c) return;
  STATE.selectedId = id;
  var days = daysSinceDate(c.last_used);
  var cat = c.category || "—";
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

  var tagsHtml = (c.tags || [])
    .map(function (t) {
      return '<span class="tag">' + esc(t) + "</span>";
    })
    .join("");

  var bodyHtml =
    c.body && c.body.trim()
      ? '<div class="body">' + c.body + "</div>"
      : '<div class="body body-empty">（无内容）</div>';

  var staleHtml = "";
  if (days > 180) {
    staleHtml =
      '<div class="stale-warn">⚠ 已超过 180 天未使用，建议验证或归档</div>';
  } else if (days > 60) {
    staleHtml =
      '<div class="stale-warn">⚠ 已超过 60 天未使用，建议检查时效</div>';
  }

  // 顶部 meta 块
  var metaHtml =
    '<div class="detail-meta">' +
    '<span class="detail-meta-item"><span class="k">类别</span><span class="v" style="color:' +
    catColor +
    '">' +
    esc(cat) +
    "</span></span>" +
    (c.type
      ? '<span class="detail-meta-item"><span class="k">类型</span><span class="v">' +
        esc(c.type) +
        "</span></span>"
      : "") +
    '<span class="detail-meta-item"><span class="k">作者</span><span class="v" style="color:' +
    ownerColor +
    '">' +
    esc(owner) +
    "</span></span>" +
    '<span class="detail-meta-item"><span class="k">状态</span><span class="v"><span class="status-badge status-' +
    esc(c.status || "done") +
    '">' +
    esc(c.status || "?") +
    "</span></span></span>" +
    "</div>";

  // 字段表
  var fields = [
    fieldRow("创建", c.created),
    fieldRow("最近使用", c.last_used),
    fieldRow("最近验证", c.last_verified),
    fieldRow("tech", c.tech),
    fieldRow("entry_type", c.entry_type),
  ].join("");

  var tagsBlock = tagsHtml
    ? '<div class="field"><span class="k">tags</span><span class="v">' +
      tagsHtml +
      "</span></div>"
    : "";

  var html =
    '<button class="close" aria-label="关闭详情">×</button>' +
    '<nav class="detail-nav" aria-label="上一张/下一张">' +
    '<button class="detail-nav-prev" title="上一张 (k)" aria-label="上一张">↑</button>' +
    '<button class="detail-nav-next" title="下一张 (j)" aria-label="下一张">↓</button>' +
    "</nav>" +
    "<h2>" +
    esc(c.title || "untitled") +
    "</h2>" +
    '<div class="id-line">' +
    esc(c.id) +
    (c.file ? " · " + esc(c.file) : "") +
    "</div>" +
    metaHtml +
    staleHtml +
    '<div style="margin-top:8px">' +
    fields +
    tagsBlock +
    "</div>" +
    bodyHtml;

  var pane = document.getElementById("detail-pane");
  pane.innerHTML = html;
  pane.classList.add("is-open");
  pane.setAttribute("aria-hidden", "false");
  // 高亮当前卡片
  highlightSelected(id);
}

function closeDetail() {
  var pane = document.getElementById("detail-pane");
  pane.classList.remove("is-open");
  pane.setAttribute("aria-hidden", "true");
  STATE.selectedId = null;
  document.querySelectorAll(".card-item.highlight").forEach(function (el) {
    el.classList.remove("highlight");
  });
}

// ════════════════════════════════════════════════════════════════
// 渲染调度
// ════════════════════════════════════════════════════════════════

function renderAll() {
  renderStale();
  renderSidebar();
  renderCharts();
  renderCards();
}
