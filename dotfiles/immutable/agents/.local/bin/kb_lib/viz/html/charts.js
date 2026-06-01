// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT
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
