// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

// ════════════════════════════════════════════════════════════════
// 配色 — 主题感知的固定色板（图表底层用确定色，便于在亮/暗主题下保持语义）
// ════════════════════════════════════════════════════════════════

var CATEGORY_COLORS = {
  general: "#5c7cfa",
  guix: "#20c997",
  emacs: "#cc5de8",
  "emacs-config": "#f06595",
  gamedev: "#ff922b",
  framework: "#22b8cf",
  feature: "#51cf66",
  debug: "#ff6b6b",
  workflow: "#fcc419",
  rust: "#fa5252",
  other: "#909296",
};
var STATUS_COLORS = {
  stable: "#51cf66",
  done: "#22b8cf",
  archived: "#cc5de8",
  stale: "#ff6b6b",
};
var TYPE_COLORS = {
  debug: "#ff6b6b",
  refactor: "#f06595",
  research: "#22b8cf",
  workflow: "#fcc419",
  feature: "#51cf66",
  config: "#5c7cfa",
};
var OWNER_COLORS = {
  human: "#ff922b",
  ai: "#5c7cfa",
  collab: "#20c997",
};
var ENTRY_COLORS = {
  mistake: "#ff6b6b",
  note: "#5c7cfa",
  ascended: "#20c997",
  none: "#adb5bd",
};

// ════════════════════════════════════════════════════════════════
// 工具
// ════════════════════════════════════════════════════════════════

function countBy(cards, key, opts) {
  opts = opts || {};
  var out = {};
  cards.forEach(function (c) {
    var v = c[key];
    if (v == null || v === "") {
      if (opts.skipNull) return;
      v = "—";
    }
    if (key === "tech") {
      String(v)
        .split(",")
        .forEach(function (t) {
          t = t.trim();
          if (t) out[t] = (out[t] || 0) + 1;
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

function topTechMap() {
  var out = {};
  TOP_TECHS.forEach(function (t) {
    out[t[0]] = t[1];
  });
  return out;
}

function chartEmpty(svg, w, h, msg) {
  if (!h) h = 60;
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.setAttribute("height", h);
  svg.innerHTML =
    '<text class="chart-empty" x="' +
    w / 2 +
    '" y="' +
    h / 2 +
    '">' +
    esc(msg) +
    "</text>";
}

// ════════════════════════════════════════════════════════════════
// 侧边栏：类别树 / 维度过滤 / 记忆概览
// ════════════════════════════════════════════════════════════════

function renderStale() {
  var bar = document.getElementById("stale-alert");
  var sStale = STATS.stale_count || 0,
    sArchive = STATS.archive_count || 0,
    staleDays = STATS.stale_threshold_days || 30,
    archiveDays = STATS.archive_threshold_days || 90;
  if (sStale === 0 && sArchive === 0) {
    bar.innerHTML = "";
    bar.style.display = "none";
    return;
  }
  bar.style.display = "block";
  bar.innerHTML =
    "<div>" +
    "<strong>⚠ 陈旧卡片</strong>" +
    "<span>" +
    staleDays +
    " 天以上未使用 <strong style='color:var(--orange)'>" +
    sStale +
    "</strong> 张 · " +
    archiveDays +
    " 天以上未使用 <strong style='color:var(--red)'>" +
    sArchive +
    "</strong> 张，建议验证或归档</span>" +
    "</div>";
}

function renderSidebar() {
  // 类别树
  var tree = countBy(CARDS, "category");
  var treeHtml = '<ul class="tree-list">';
  var cats = Object.keys(tree).sort();
  var isAllActive = STATE.selectedCategory === null;
  treeHtml +=
    '<li class="' +
    (isAllActive ? "active" : "") +
    '" data-cat="" tabindex="0" role="button"><span>全部</span><span class="count">' +
    CARDS.length +
    "</span></li>";
  cats.forEach(function (k) {
    var active = STATE.selectedCategory === k ? " active" : "";
    var dotColor = CATEGORY_COLORS[k] || "var(--accent)";
    treeHtml +=
      '<li class="' +
      active +
      '" data-cat="' +
      esc(k) +
      '" tabindex="0" role="button">' +
      '<span><i class="cat-dot" style="background:' +
      dotColor +
      '"></i>' +
      esc(k) +
      "</span>" +
      '<span class="count">' +
      tree[k] +
      "</span>" +
      "</li>";
  });
  treeHtml += "</ul>";
  document.getElementById("tree-list").innerHTML = treeHtml;
  document.querySelectorAll("#tree-list li").forEach(function (li) {
    var handler = function () {
      var v = li.dataset.cat;
      STATE.selectedCategory = v || null;
      if (v) STATE.filter.category = v;
      else delete STATE.filter.category;
      renderAll();
    };
    li.addEventListener("click", handler);
    li.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        handler();
      }
    });
  });

  // 维度过滤
  var facetFields = [
    { key: "status", title: "状态", colorMap: STATUS_COLORS },
    { key: "type", title: "类型", colorMap: TYPE_COLORS },
    { key: "owner", title: "作者", colorMap: OWNER_COLORS },
    { key: "entry_type", title: "条目类型", colorMap: ENTRY_COLORS },
    { key: "tech", title: "技术栈 (Top 8)", colorMap: null, top: 8 },
  ];
  var html = "";
  facetFields.forEach(function (f) {
    var data =
      f.key === "tech"
        ? topTechMap()
        : countBy(CARDS, f.key, { skipNull: true });
    var keys = Object.keys(data).sort(function (a, b) {
      return data[b] - data[a];
    });
    if (f.top) keys = keys.slice(0, f.top);
    if (keys.length === 0) return;
    html += "<h3>" + esc(f.title) + '</h3><div class="facet">';
    keys.forEach(function (k) {
      var active = STATE.filter[f.key] === k ? " active" : "";
      var colorDot =
        f.colorMap && f.colorMap[k]
          ? ' style="border-color:' + f.colorMap[k] + '"'
          : "";
      html +=
        '<button class="' +
        active +
        '" data-facet="' +
        esc(f.key) +
        '" data-val="' +
        esc(k) +
        '"' +
        colorDot +
        ">" +
        esc(k) +
        '<span class="n">' +
        data[k] +
        "</span></button>";
    });
    html += "</div>";
  });
  html +=
    '<h3>操作</h3><div class="facet"><button data-action="reset">↺ 重置全部过滤</button></div>';
  document.getElementById("facets").innerHTML = html;
  document.querySelectorAll("#facets button[data-facet]").forEach(function (b) {
    b.addEventListener("click", function () {
      var k = b.dataset.facet,
        v = b.dataset.val;
      if (STATE.filter[k] === v) delete STATE.filter[k];
      else STATE.filter[k] = v;
      if (k === "category") STATE.selectedCategory = v || null;
      renderAll();
    });
  });
  document
    .querySelectorAll('#facets button[data-action="reset"]')
    .forEach(function (b) {
      b.addEventListener("click", function () {
        STATE.filter = {};
        STATE.search = "";
        STATE.selectedCategory = null;
        STATE.sort = "default";
        var si = document.getElementById("search-input");
        if (si) si.value = "";
        var ss = document.getElementById("sort-select");
        if (ss) ss.value = "default";
        renderAll();
      });
    });
}

// ════════════════════════════════════════════════════════════════
// 图表分发
// ════════════════════════════════════════════════════════════════

function renderCharts() {
  var visible = getVisibleCards();
  renderBarChart(
    "chart-category",
    countBy(visible, "category"),
    CATEGORY_COLORS,
    160,
  );
  renderBarChart("chart-type", countBy(visible, "type"), TYPE_COLORS, 160);
  renderBarChart("chart-owner", countBy(visible, "owner"), OWNER_COLORS, 160);
  renderBarChart("chart-tech", countBy(visible, "tech"), null, 200);
  renderBarChart(
    "chart-entry",
    countBy(visible, "entry_type", { skipNull: true }),
    ENTRY_COLORS,
    160,
  );
  renderBarChart(
    "chart-status",
    countBy(visible, "status"),
    STATUS_COLORS,
    160,
  );
  renderTimeline(visible);
  renderHeatmap(visible);
  renderForceGraph(visible);
}

// ════════════════════════════════════════════════════════════════
// 水平条形图（共享）
// ════════════════════════════════════════════════════════════════

function renderBarChart(svgId, data, colors, defaultH) {
  var svg = document.getElementById(svgId);
  if (!svg) return;
  var w = svg.clientWidth || 360;
  var pad = { l: 96, r: 36, t: 6, b: 6 };
  var entries = Object.entries(data).sort(function (a, b) {
    return b[1] - a[1];
  });
  if (entries.length === 0) {
    chartEmpty(svg, w, 60, "暂无数据");
    return;
  }
  var max = entries[0][1];
  var barH = Math.max(
    14,
    Math.min(24, (defaultH - pad.t - pad.b) / entries.length),
  );
  var chartW = w - pad.l - pad.r;
  var y = pad.t;
  var html = "";
  entries.forEach(function (e, i) {
    var name = e[0],
      count = e[1];
    var barW = max > 0 ? (count / max) * chartW : 0;
    var color = colors && colors[name] ? colors[name] : "var(--accent)";
    html +=
      '<text x="' +
      (pad.l - 8) +
      '" y="' +
      (y + barH / 2 + 4) +
      '" fill="var(--text)" font-size="11" text-anchor="end">' +
      esc(name) +
      "</text>" +
      '<rect class="bar-rect" x="' +
      pad.l +
      '" y="' +
      (y + 2) +
      '" width="' +
      Math.max(barW, 2) +
      '" height="' +
      (barH - 6) +
      '" fill="' +
      color +
      '" rx="3" opacity="0.88"/>' +
      '<text x="' +
      (pad.l + Math.max(barW, 2) + 6) +
      '" y="' +
      (y + barH / 2 + 4) +
      '" fill="var(--text-dim)" font-size="11" font-weight="500">' +
      count +
      "</text>";
    y += barH;
  });
  svg.setAttribute(
    "height",
    Math.max(80, entries.length * barH + pad.t + pad.b),
  );
  svg.innerHTML = html;
}

// ════════════════════════════════════════════════════════════════
// 时间线（双 Y 轴）
// ════════════════════════════════════════════════════════════════

function renderTimeline(visible) {
  var svg = document.getElementById("chart-timeline");
  if (!svg) return;
  var w = svg.clientWidth || 720;
  var h = 260;
  var pad = { l: 50, r: 50, t: 28, b: 36 };
  function byMonth(cards, key) {
    var m = {};
    cards.forEach(function (c) {
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
  var keys = Array.from(
    new Set(
      [].concat(Object.keys(created), Object.keys(used), Object.keys(verified)),
    ),
  ).sort();
  if (keys.length === 0) {
    chartEmpty(svg, w, h, "暂无时间数据");
    return;
  }
  function vals(map) {
    return keys.map(function (k) {
      return map[k] || 0;
    });
  }
  var vC = vals(created),
    vU = vals(used),
    vV = vals(verified);
  var maxLeft = Math.max.apply(null, vC) || 1;
  var maxRight = Math.max.apply(null, vU.concat(vV)) || 1;
  var chartW = w - pad.l - pad.r;
  var chartH = h - pad.t - pad.b;
  function xAt(i) {
    return (
      pad.l +
      (keys.length === 1 ? chartW / 2 : (i * chartW) / (keys.length - 1))
    );
  }
  function yLeft(v) {
    return pad.t + chartH - (v / maxLeft) * chartH;
  }
  function yRight(v) {
    return pad.t + chartH - (v / maxRight) * chartH;
  }
  function path(vals, yFn) {
    return vals
      .map(function (v, i) {
        return (
          (i === 0 ? "M" : "L") + xAt(i).toFixed(1) + "," + yFn(v).toFixed(1)
        );
      })
      .join(" ");
  }
  // 平滑曲线（用 Catmull-Rom 转换三次贝塞尔）
  function smoothPath(vals, yFn) {
    if (vals.length < 2) return path(vals, yFn);
    var pts = vals.map(function (v, i) {
      return { x: xAt(i), y: yFn(v) };
    });
    var d = "M" + pts[0].x.toFixed(1) + "," + pts[0].y.toFixed(1);
    for (var i = 0; i < pts.length - 1; i++) {
      var p0 = pts[i - 1] || pts[i];
      var p1 = pts[i];
      var p2 = pts[i + 1];
      var p3 = pts[i + 2] || p2;
      var cp1x = p1.x + (p2.x - p0.x) / 6;
      var cp1y = p1.y + (p2.y - p0.y) / 6;
      var cp2x = p2.x - (p3.x - p1.x) / 6;
      var cp2y = p2.y - (p3.y - p1.y) / 6;
      d +=
        "C" +
        cp1x.toFixed(1) +
        "," +
        cp1y.toFixed(1) +
        " " +
        cp2x.toFixed(1) +
        "," +
        cp2y.toFixed(1) +
        " " +
        p2.x.toFixed(1) +
        "," +
        p2.y.toFixed(1);
    }
    return d;
  }
  var html = "";
  // 网格
  for (var g = 0; g <= 4; g++) {
    var yy = pad.t + (g / 4) * chartH;
    html +=
      '<line x1="' +
      pad.l +
      '" y1="' +
      yy +
      '" x2="' +
      (w - pad.r) +
      '" y2="' +
      yy +
      '" stroke="var(--grid-line)" stroke-width="1"/>';
  }
  // 数据曲线
  html +=
    '<path d="' +
    smoothPath(vC, yLeft) +
    '" stroke="var(--green)" fill="none" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>';
  html +=
    '<path d="' +
    smoothPath(vU, yRight) +
    '" stroke="var(--cyan)" fill="none" stroke-width="2" stroke-dasharray="5 3" stroke-linejoin="round" stroke-linecap="round"/>';
  html +=
    '<path d="' +
    smoothPath(vV, yRight) +
    '" stroke="var(--orange)" fill="none" stroke-width="2" stroke-dasharray="2 2" stroke-linejoin="round" stroke-linecap="round"/>';
  // 节点
  var palette = ["var(--green)", "var(--cyan)", "var(--orange)"];
  [vC, vU, vV].forEach(function (vals, idx) {
    vals.forEach(function (v, i) {
      if (v > 0) {
        var yy = idx === 0 ? yLeft(v) : yRight(v);
        html +=
          '<circle cx="' +
          xAt(i).toFixed(1) +
          '" cy="' +
          yy.toFixed(1) +
          '" r="3" fill="' +
          palette[idx] +
          '" stroke="var(--bg-panel)" stroke-width="1.5"/>';
      }
    });
  });
  // X 轴标签
  keys.forEach(function (k, i) {
    if (
      keys.length > 12 &&
      i % Math.ceil(keys.length / 8) !== 0 &&
      i !== keys.length - 1
    )
      return;
    html +=
      '<text x="' +
      xAt(i).toFixed(1) +
      '" y="' +
      (h - 12) +
      '" fill="var(--text-dim)" font-size="9.5" text-anchor="middle">' +
      esc(k) +
      "</text>";
  });
  // Y 轴刻度
  for (var g2 = 0; g2 <= 4; g2++) {
    var vl = Math.round((g2 / 4) * maxLeft);
    var vr = Math.round((g2 / 4) * maxRight);
    var yy2 = pad.t + chartH - (g2 / 4) * chartH;
    html +=
      '<text x="' +
      (pad.l - 6) +
      '" y="' +
      (yy2 + 3) +
      '" fill="var(--green)" font-size="9.5" text-anchor="end" font-weight="500">' +
      vl +
      "</text>";
    html +=
      '<text x="' +
      (w - pad.r + 6) +
      '" y="' +
      (yy2 + 3) +
      '" fill="var(--cyan)" font-size="9.5" font-weight="500">' +
      vr +
      "</text>";
  }
  // 图例
  var legendItems = [
    { color: "var(--green)", label: "created", x: 0 },
    { color: "var(--cyan)", label: "used", x: 76 },
    { color: "var(--orange)", label: "verified", x: 138 },
  ];
  var legendX = 16;
  html += '<g transform="translate(' + legendX + ',10)">';
  legendItems.forEach(function (it) {
    html +=
      '<line x1="' +
      it.x +
      '" y1="5" x2="' +
      (it.x + 18) +
      '" y2="5" stroke="' +
      it.color +
      '" stroke-width="2.5" stroke-linecap="round"/>' +
      '<text x="' +
      (it.x + 24) +
      '" y="9" fill="var(--text)" font-size="10.5">' +
      it.label +
      "</text>";
  });
  html += "</g>";
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.setAttribute("height", h);
  svg.innerHTML = html;
}

// ════════════════════════════════════════════════════════════════
// 月度热力图
// ════════════════════════════════════════════════════════════════

function renderHeatmap(visible) {
  var svg = document.getElementById("chart-heatmap");
  if (!svg) return;
  var counts = {};
  visible.forEach(function (c) {
    String(c.tech || "")
      .split(",")
      .forEach(function (t) {
        t = t.trim();
        if (t) counts[t] = (counts[t] || 0) + 1;
      });
  });
  var techs = Object.keys(counts).filter(function (t) {
    return counts[t] >= 2;
  });
  techs.sort(function (a, b) {
    return counts[b] - counts[a];
  });
  var rows = Math.min(8, techs.length);
  if (rows === 0) {
    chartEmpty(svg, 600, 60, "暂无技术栈热力数据（频次 ≥ 2 的 tech 不足）");
    return;
  }
  techs = techs.slice(0, rows);
  var now = new Date();
  var months = [];
  for (var i = 5; i >= 0; i--) {
    var d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    months.push(
      d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0"),
    );
  }
  var ymInWindow = function (s) {
    return s && s.length >= 7 && months.indexOf(s.substring(0, 7)) >= 0
      ? s.substring(0, 7)
      : "";
  };
  var grid = {};
  visible.forEach(function (c) {
    String(c.tech || "")
      .split(",")
      .forEach(function (t) {
        t = t.trim();
        if (!t) return;
        var c_ym = ymInWindow(c.created || "");
        var l_ym = ymInWindow(c.last_used || "");
        var chosen = "";
        if (c_ym && l_ym) chosen = l_ym > c_ym ? l_ym : c_ym;
        else if (c_ym) chosen = c_ym;
        else if (l_ym) chosen = l_ym;
        if (chosen) grid[t + "|" + chosen] = (grid[t + "|" + chosen] || 0) + 1;
      });
  });
  var maxV = 0;
  Object.keys(grid).forEach(function (k) {
    if (grid[k] > maxV) maxV = grid[k];
  });
  var labelW = 76,
    cellW = 28,
    cellH = 16,
    padT = 22;
  var w = labelW + months.length * cellW + 20;
  var h = padT + rows * cellH + 20;
  var html = "";
  months.forEach(function (m, i) {
    html +=
      '<text x="' +
      (labelW + i * cellW + cellW / 2) +
      '" y="14" fill="var(--text-dim)" font-size="8.5" text-anchor="middle">' +
      esc(m.substring(5)) +
      "</text>";
  });
  techs.forEach(function (t, ri) {
    var yy = padT + ri * cellH;
    html +=
      '<text x="' +
      (labelW - 6) +
      '" y="' +
      (yy + cellH / 2 + 3) +
      '" fill="var(--text)" font-size="9.5" text-anchor="end">' +
      esc(t) +
      "</text>";
    months.forEach(function (m, ci) {
      var v = grid[t + "|" + m] || 0;
      var intensity = maxV > 0 ? Math.log(1 + v) / Math.log(1 + maxV) : 0;
      var color =
        v === 0
          ? "var(--bg-elevated)"
          : "rgba(92, 124, 250, " + (0.18 + intensity * 0.82).toFixed(2) + ")";
      html +=
        '<rect x="' +
        (labelW + ci * cellW + 1) +
        '" y="' +
        (yy + 1) +
        '" width="' +
        (cellW - 2) +
        '" height="' +
        (cellH - 2) +
        '" fill="' +
        color +
        '" rx="2">' +
        (v > 0
          ? "<title>" + esc(t) + " · " + esc(m) + ": " + v + " 张</title>"
          : "") +
        "</rect>";
      if (v > 0) {
        html +=
          '<text x="' +
          (labelW + ci * cellW + cellW / 2) +
          '" y="' +
          (yy + cellH / 2 + 3) +
          '" fill="rgba(255,255,255,0.92)" font-size="8.5" text-anchor="middle" font-weight="500">' +
          v +
          "</text>";
      }
    });
  });
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.setAttribute(
    "style",
    "max-width: 360px; height: auto; margin: 0 auto; display: block;",
  );
  svg.innerHTML = html;
}
