# SVG 多状态机 + 圆圈+标签布局范式

## 常见痛点:状态圆里掉进标签

`npx hyperframes inspect` 会扫 SVG 里 `<text>` 的位置,如果一个标签的 bounding box 落入另一个状态圆的范围(<circle> 的 cx-r 到 cx+r),会报 `content_overlap` warning。

**经验规则**: 圆圈 r=60,r=80 的状态圆 → 标签的 (x, y) 必须在 cx±r 之外 + 至少 10px 留白。常见做法: 标签放在圆的**外侧**(y 偏离 cy + r + 20)。

```svg
<!-- BAD: 标签 x=855 y=265 落入 circle(cx=860 cy=240 r=60) -->
<circle cx="860" cy="240" r="60" .../>
<text x="855" y="265">:set</text>

<!-- GOOD: 标签移到圆外 -->
<text x="1050" y="265">:set</text>
```

## 7 状态状态机范式(Evil / Magit / Org 模式通用)

以 Evil-mode 6 状态 + 文本对象节点为例:

```svg
<svg viewBox="0 0 1500 760">
  <defs>
    <marker id="arr" markerWidth="12" markerHeight="12" refX="10" refY="6" orient="auto">
      <path d="M0,0 L10,6 L0,12 Z" fill="#7ee787"/>
    </marker>
  </defs>

  <!-- 1. 箭头先画,让它在节点下面 -->
  <g id="arrows" fill="none" stroke-width="2.5">
    <path d="M460,240 Q... ... 380,140" stroke="#7ee787" marker-end="url(#arr)"/>
    ...
  </g>

  <!-- 2. 标签组,放圆外 -->
  <g id="labels" font-family="JetBrains Mono" font-size="18" fill="#8b949e" text-anchor="middle">
    <text x="290" y="125">i</text>          <!-- 圆 cx=200 cy=160 r=64 → 圆外 -->
    <text x="570" y="125">v / R / C-c C-z</text>
    ...
  </g>

  <!-- 3. 状态节点最后画,盖在箭头上面 -->
  <g id="state-normal">
    <circle cx="460" cy="240" r="80" fill="#7ee78722" stroke="#7ee787" stroke-width="3"/>
    <text x="460" y="234" text-anchor="middle" font-family="Inter" font-size="32" font-weight="800" fill="#7ee787">N</text>
    <text x="460" y="270" text-anchor="middle" font-family="JetBrains Mono" font-size="16" fill="#e6edf3">Normal</text>
  </g>
  ...
</svg>
```

GSAP 进场顺序:
1. 中心状态 `fromTo({opacity:0, scale:0.5}, {opacity:1, scale:1, ease:'back.out(1.7)'})`
2. 所有箭头 `fromTo({strokeDasharray:N, strokeDashoffset:N}, {strokeDashoffset:0, stagger:0.1})`
3. 外围状态 stagger 入场(0.15-0.18s 一个)
4. 标签 opacity 显现(stagger 0.05)

## 双向链接网络图范式(Org Roam / 知识图谱)

9 节点 + 12 条边的力导向图(伪力导向,手工布局坐标即可):

```svg
<svg viewBox="0 0 800 760">
  <!-- 边先画,这样节点覆盖在边上面 -->
  <g id="links" stroke="#30363d" stroke-width="2" fill="none">
    <line x1="400" y1="200" x2="220" y2="340"/>
    ...
  </g>

  <!-- 节点 -->
  <g id="nodes">
    <g><circle cx="400" cy="200" r="46" fill="#7ee787" fill-opacity="0.18" stroke="#7ee787" stroke-width="2.5"/>
       <text x="400" y="206" text-anchor="middle" fill="#7ee787" font-family="JetBrains Mono" font-size="16" font-weight="700">中心</text></g>
    ...
  </g>

  <!-- 中心节点脉冲(可选,做出"知识图谱是活的"的感觉) -->
  <circle id="graph-pulse" cx="400" cy="200" r="40" fill="none" stroke="#7ee787" stroke-width="2" opacity="0"/>
</svg>
```

GSAP 进场: 中心 → 一圈边 → 外环节点 → 二圈边 → 最外环节点。中心节点出现后用:

```js
tl.fromTo('#graph-pulse',
  { opacity: 0, attr: { r: 40 } },
  { opacity: 0.7, attr: { r: 90 }, duration: 1.5, ease: 'power2.out',
    repeat: 4, yoyo: true }, '+=0.5')
```

## Org Roam 5 类节点配色

| 颜色 | 语义 | 例子 |
|---|---|---|
| `#7ee787` 绿 | 核心概念 | Elisp, use-package |
| `#d2a8ff` 紫 | 语法/结构 | Macro, Closure |
| `#ffa657` 橙 | 工具/流程 | Startup, Package |
| `#79c0ff` 蓝 | 生态包 | Roam |
| `#56d4dd` 青 | 日常工作流 | Capture, Daily |

右侧图例(5 行 dot+label)用同色,辅助观众快速读图。
