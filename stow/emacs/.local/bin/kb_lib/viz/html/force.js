// SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
// SPDX-License-Identifier: MIT

// ════════════════════════════════════════════════════════════════
// 配置
// ════════════════════════════════════════════════════════════════

var FORCE = {
  REPULSION: 24000,
  GRAVITY: 0.008,
  SPRING_K: 0.04,
  SPRING_L: 130,
  DAMPING: 0.88,
  ITERATIONS: 300,
  ALPHA_INIT: 1.0,
  ALPHA_MIN: 0.02,
  ZOOM_MIN: 0.3,
  ZOOM_MAX: 4,
  ZOOM_WHEEL_STEP: 1.08,
  ZOOM_BTN_STEP: 1.18,
  ZOOM_LERP: 0.22,
};
var GCURR = { tx: 0, ty: 0, k: 1 };
var GTGT = { tx: 0, ty: 0, k: 1 };
var gAnim = 0;

function applyGTrans() {
  var svg = document.getElementById("graph-svg");
  if (!svg) return;
  var g = svg.querySelector(".viewport");
  if (!g) return;
  g.setAttribute(
    "transform",
    "translate(" + GCURR.tx + "," + GCURR.ty + ") " + "scale(" + GCURR.k + ")",
  );
}

function setGTgt(tx, ty, k) {
  GTGT.tx = tx;
  GTGT.ty = ty;
  GTGT.k = k;
  if (!gAnim) gAnim = requestAnimationFrame(animGTrans);
}

function animGTrans() {
  var dx = GTGT.tx - GCURR.tx;
  var dy = GTGT.ty - GCURR.ty;
  var dk = GTGT.k - GCURR.k;
  if (Math.abs(dx) < 0.1 && Math.abs(dy) < 0.1 && Math.abs(dk) < 0.001) {
    GCURR.tx = GTGT.tx;
    GCURR.ty = GTGT.ty;
    GCURR.k = GTGT.k;
    applyGTrans();
    gAnim = 0;
    return;
  }
  var f = FORCE.ZOOM_LERP;
  GCURR.tx += dx * f;
  GCURR.ty += dy * f;
  GCURR.k += dk * f;
  applyGTrans();
  gAnim = requestAnimationFrame(animGTrans);
}

function zoomGraphAt(cx, cy, factor) {
  var newK = Math.max(
    FORCE.ZOOM_MIN,
    Math.min(FORCE.ZOOM_MAX, GTGT.k * factor),
  );
  if (newK === GTGT.k) return;
  var real = newK / GTGT.k;
  setGTgt(cx - (cx - GTGT.tx) * real, cy - (cy - GTGT.ty) * real, newK);
}

function resetGraph() {
  setGTgt(0, 0, 1);
}

// ════════════════════════════════════════════════════════════════
// 渲染入口
// ════════════════════════════════════════════════════════════════

function renderForceGraph(visible) {
  var svg = document.getElementById("graph-svg");
  if (!svg) return;

  // 1. 收集标签频次
  var tagCount = {},
    tagCards = {};
  visible.forEach(function (c) {
    (c.tags || []).forEach(function (t) {
      if (!t) return;
      if (/^(debug|workflow|research|refactor|feature|config)$/i.test(t))
        return;
      if (
        /^(general|guix|emacs|framework|gamedev|emacs-config)$/i.test(t)
      )
        return;
      if (t === c.owner) return;
      if (t === c.category) return;
      tagCount[t] = (tagCount[t] || 0) + 1;
      if (!tagCards[t]) tagCards[t] = [];
      tagCards[t].push(c);
    });
  });
  var tags = Object.keys(tagCount).sort(function (a, b) {
    return tagCount[b] - tagCount[a];
  });
  var topN = Math.min(tags.length, 30);
  tags = tags.slice(0, topN);
  if (tags.length === 0) {
    var w = svg.clientWidth || 800;
    chartEmpty(svg, w, 480, "暂无标签数据");
    return;
  }

  // 2. 共现边
  var maxCount = tagCount[tags[0]];
  var cooc = {};
  visible.forEach(function (c) {
    var t = (c.tags || []).filter(function (x) {
      return tagCount[x];
    });
    for (var i = 0; i < t.length; i++) {
      for (var j = i + 1; j < t.length; j++) {
        var key = [t[i], t[j]].sort().join("::");
        cooc[key] = (cooc[key] || 0) + 1;
      }
    }
  });

  // 3. 节点初始布局
  var w = svg.clientWidth || 800;
  var h = parseInt(getComputedStyle(svg).height) || 480;
  var cx = w / 2,
    cy = h / 2;
  var nodes = tags.map(function (t, i) {
    var size = 7 + (tagCount[t] / maxCount) * 16;
    var cols = Math.ceil(Math.sqrt(tags.length));
    var rows = Math.ceil(tags.length / cols);
    var padL = w * 0.12,
      padT = h * 0.12;
    var usableW = w - 2 * padL;
    var usableH = h - 2 * padT;
    var cellW = usableW / cols;
    var cellH = usableH / rows;
    var jitterX = (((i * 31) % 100) / 100) * cellW * 0.4 - cellW * 0.2;
    var jitterY = (((i * 47) % 100) / 100) * cellH * 0.4 - cellH * 0.2;
    return {
      tag: t,
      count: tagCount[t],
      size: size,
      x: padL + ((i % cols) + 0.5) * cellW + jitterX,
      y: padT + (Math.floor(i / cols) + 0.5) * cellH + jitterY,
      vx: 0,
      vy: 0,
      fixed: false,
    };
  });
  var nodeMap = {};
  nodes.forEach(function (n) {
    nodeMap[n.tag] = n;
  });
  var edges = [];
  Object.keys(cooc).forEach(function (key) {
    var parts = key.split("::");
    var a = nodeMap[parts[0]],
      b = nodeMap[parts[1]];
    if (a && b) edges.push({ a: a, b: b, w: cooc[key] });
  });

  // 4. Eades 简化算法迭代
  var alpha = FORCE.ALPHA_INIT;
  for (var iter = 0; iter < FORCE.ITERATIONS; iter++) {
    var alphaNow = Math.max(alpha, FORCE.ALPHA_MIN);
    for (var i = 0; i < nodes.length; i++) {
      var n1 = nodes[i];
      if (n1.fixed) continue;
      for (var j = 0; j < nodes.length; j++) {
        if (i === j) continue;
        var n2 = nodes[j];
        var dx = n1.x - n2.x,
          dy = n1.y - n2.y;
        var d2 = dx * dx + dy * dy;
        if (d2 < 1) d2 = 1;
        var f = FORCE.REPULSION / d2;
        n1.vx += (dx / Math.sqrt(d2)) * f * alphaNow;
        n1.vy += (dy / Math.sqrt(d2)) * f * alphaNow;
      }
    }
    edges.forEach(function (e) {
      var dx = e.b.x - e.a.x,
        dy = e.b.y - e.a.y;
      var d = Math.sqrt(dx * dx + dy * dy) || 1;
      var f = FORCE.SPRING_K * (d - FORCE.SPRING_L) * Math.min(e.w / 5, 1);
      if (!e.a.fixed) {
        e.a.vx += (dx / d) * f;
        e.a.vy += (dy / d) * f;
      }
      if (!e.b.fixed) {
        e.b.vx -= (dx / d) * f;
        e.b.vy -= (dy / d) * f;
      }
    });
    nodes.forEach(function (n) {
      if (n.fixed) return;
      n.vx += (cx - n.x) * FORCE.GRAVITY;
      n.vy += (cy - n.y) * FORCE.GRAVITY;
    });
    nodes.forEach(function (n) {
      if (n.fixed) return;
      n.vx *= FORCE.DAMPING;
      n.vy *= FORCE.DAMPING;
      n.x += n.vx;
      n.y += n.vy;
      n.x = Math.max(n.size + 4, Math.min(w - n.size - 4, n.x));
      n.y = Math.max(n.size + 13, Math.min(h - n.size - 13, n.y));
    });
    alpha *= 0.995;
  }

  // 5. 输出 SVG
  var html = '<g class="viewport">';
  edges.forEach(function (e) {
    var op = Math.min(0.18 + e.w * 0.07, 0.55);
    var sw = Math.min(0.8 + e.w * 0.4, 2.5);
    html +=
      '<line x1="' +
      e.a.x.toFixed(1) +
      '" y1="' +
      e.a.y.toFixed(1) +
      '" x2="' +
      e.b.x.toFixed(1) +
      '" y2="' +
      e.b.y.toFixed(1) +
      '" stroke="var(--accent)" stroke-width="' +
      sw.toFixed(2) +
      '" opacity="' +
      op.toFixed(2) +
      '"/>';
  });
  nodes.forEach(function (n) {
    var cat =
      tagCards[n.tag] && tagCards[n.tag][0]
        ? tagCards[n.tag][0].category || "other"
        : "other";
    var color = CATEGORY_COLORS[cat] || "var(--accent)";
    html +=
      '<g class="gnode" data-tag="' +
      esc(n.tag) +
      '" style="cursor:pointer">' +
      '<circle cx="' +
      n.x.toFixed(1) +
      '" cy="' +
      n.y.toFixed(1) +
      '" r="' +
      n.size +
      '" fill="' +
      color +
      '" fill-opacity="0.85" stroke="var(--bg-panel)" stroke-width="1.5"/>' +
      '<text x="' +
      n.x.toFixed(1) +
      '" y="' +
      (n.y + n.size + 12).toFixed(1) +
      '" fill="var(--text-dim)" font-size="10.5" text-anchor="middle" font-weight="500">' +
      esc(n.tag) +
      " · " +
      n.count +
      "</text>" +
      "</g>";
  });
  html += "</g>";
  svg.innerHTML = html;
  svg.setAttribute("width", w);
  svg.setAttribute("height", h);
  svg.setAttribute("viewBox", "0 0 " + w + " " + h);
  svg.style.maxWidth = "100%";
  svg.style.height = "auto";
  resetGraph();

  // 6. Tooltip
  var tt = document.getElementById("graph-tooltip");
  svg.querySelectorAll(".gnode").forEach(function (g) {
    g.addEventListener("mouseenter", function (e) {
      var tag = g.dataset.tag;
      var list = (tagCards[tag] || []).slice(0, 5);
      var html2 =
        '<div class="tt-title">' +
        esc(tag) +
        '</div><div class="tt-meta bold">出现 ' +
        tagCount[tag] +
        " 次</div>";
      list.forEach(function (c) {
        html2 +=
          '<div class="tt-meta">· ' + esc(c.title.substring(0, 48)) + "</div>";
      });
      if ((tagCards[tag] || []).length > 5)
        html2 +=
          '<div class="tt-meta">… 还有 ' +
          ((tagCards[tag] || []).length - 5) +
          " 张</div>";
      tt.innerHTML = html2;
      tt.style.display = "block";
    });
    g.addEventListener("mousemove", function (e) {
      tt.style.left = Math.min(e.clientX + 14, window.innerWidth - 300) + "px";
      tt.style.top = e.clientY + 14 + "px";
    });
    g.addEventListener("mouseleave", function () {
      tt.style.display = "none";
    });
    // 节点点击 → 应用到过滤
    g.addEventListener("click", function () {
      // 把标签写入搜索框，触发过滤
      var si = document.getElementById("search-input");
      if (si) {
        si.value = tag;
        onSearch(tag);
      }
    });
  });

  // 7. 缩放
  svg.addEventListener(
    "wheel",
    function (e) {
      e.preventDefault();
      var rect = svg.getBoundingClientRect();
      var f = e.deltaY < 0 ? FORCE.ZOOM_WHEEL_STEP : 1 / FORCE.ZOOM_WHEEL_STEP;
      zoomGraphAt(e.clientX - rect.left, e.clientY - rect.top, f);
    },
    { passive: false },
  );

  // 8. 拖拽
  var drag = null;
  svg.addEventListener("mousedown", function (e) {
    if (e.target.closest(".gnode")) return;
    drag = { dx: e.clientX - GCURR.tx, dy: e.clientY - GCURR.ty };
  });
  window.addEventListener("mousemove", function (e) {
    if (!drag) return;
    GCURR.tx = e.clientX - drag.dx;
    GCURR.ty = e.clientY - drag.dy;
    GTGT.tx = GCURR.tx;
    GTGT.ty = GCURR.ty;
    applyGTrans();
  });
  window.addEventListener("mouseup", function () {
    drag = null;
  });
  document.querySelectorAll(".graph-controls button").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var r = svg.getBoundingClientRect();
      var mx = r.width / 2,
        my = r.height / 2;
      var a = btn.dataset.zoom;
      if (a === "in") zoomGraphAt(mx, my, FORCE.ZOOM_BTN_STEP);
      else if (a === "out") zoomGraphAt(mx, my, 1 / FORCE.ZOOM_BTN_STEP);
      else resetGraph();
    });
  });
}
