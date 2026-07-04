---
name: hyperframes-cli / lint-validate-inspect-recipes
description: Common failure modes of `hyperframes lint` / `validate` / `inspect` and the fix recipes for each. Read this the first time one of the three gates returns non-zero, BEFORE re-authoring scenes.
---

# Lint / Validate / Inspect 失败修复 Recipes

三个门控的分工:

- `lint` —— 静态检查(数据属性、轨道、GSAP 时间线)。
- `validate` —— 运行时 + WCAG 对比度。
- `inspect` —— 真实渲染抽样,布局溢出/裁切。

修复顺序: lint → validate → inspect。**修复 lint 之前不要 render**,否则会把浪费 90+ 秒渲染时间。

## 1. `lint` 必修复

### `timed_element_missing_clip_class [scene_id]`

**症状**: `<section id="c0" data-start="0" data-duration="8">` 没加 `class="clip"`,渲染时会整段一直显示(不按时间窗口隐藏)。

**原因**: HyperFrames runtime 靠 `.clip` class 控制可见性。`data-start`/`data-duration` 只是元数据,`class="clip"` 才是"按时显示"的开关。

**修复**: 给所有 `<section>` 加 `class="scene clip"`(双 class 不冲突)。批量修:

```bash
python3 -c "
import re, sys
p = sys.argv[1]
with open(p) as f: s = f.read()
s = re.sub(r'(<section id=\"c[a-z0-9]+\" class=\")scene(\")', r'\1scene clip\2', s)
with open(p, 'w') as f: f.write(s)
" index.html
```

### `font_family_without_font_face`

**症状**: 报 `font families used without @font-face declaration: noto sans sc, -apple-system, fira code`。

**原因**: HyperFrames 的字体编译器只把内置列表里的字体打包进视频,其他字体在浏览器里 fallback 到 generic,导致字体不一致。

**内置字体白名单**:`Inter`, `JetBrains Mono`, `Fira Code`(部分版本支持),系统字体(`-apple-system`, `system-ui`, `sans-serif`, `monospace`)。

**修复**: 把声明换成白名单内字体,而不是加 `@font-face`:

```css
/* ❌ 报错 */
font-family: "Inter", "Noto Sans SC", -apple-system, sans-serif;
font-family: "JetBrains Mono", "Fira Code", monospace;

/* ✅ 干净 */
font-family: "Inter", sans-serif;
font-family: "JetBrains Mono", monospace;
```

中文字符靠 Inter 的 CJK fallback 处理,不要在 font-family 里硬塞 Noto Sans SC。

### `overlapping_gsap_tweens`

**症状**: 报 `GSAP tweens overlap on "#xxx" for opacity between 30.10s and 30.60s`。

**修复策略**(按优先级):

1. **缩短前一个 tween** 或 **后移后一个**:真正消除重叠
2. **加 `overwrite: "auto"`**:在后面的 tween 上加,让 GSAP 自动覆盖(不是真的修复重叠,而是告诉 lint 接受)
3. **拆 selector 让它们不冲突**:用更精确的 selector(比如 `#e4 .text code` 而不是 `#c1b .eval-step .text code`)

如果 lint 看起来是误报(两个 tween 操作的子元素 selector 不同),优先用策略 3 拆 selector,再用 `overwrite: "auto"` 兜底。

### `composition_file_too_large` / `timeline_track_too_dense`

**症状**: `index.html` 超过 ~500 行 / 单 track 上 clip 数过多。

**这是 warning,不是 error**。试水版/单文件版可以忽略。规模化生产时:

- 拆 sub-composition:把每个 scene 写成独立 `<template>`,主 index.html 用 `<div data-composition-id="x" data-composition-src="compositions/x.html">` 挂载
- 多 track 分配:音频/字幕/BGM 各占一个 track,避免主 track 过密

## 2. `validate` 必修复

### WCAG 对比度警告(多个)

**症状**: 报 `text "xxx" — 3.85:1 (need 4.5:1, t=80s)`。

**修复**: 把灰文字从 `#6e7681` → `#a5acb4` 通常就过。在 GitHub Dark 调色板里:

| 用途 | 最低色值 |
|---|---|
| 背景层文字(注释) | `#a5acb4` |
| 次要标签 | `#b1bac4` |
| 强调文字(白) | `#e6edf3` |

**键帽陷阱**: 浅底深字在 validate 里反而报对比度低,因为它把 backgroundColor 算成了字色,字色算成了背景。**这是工具误报**,亮底配 `#0a0c0d` 在视觉上完全 OK,无需修改。

### `Failed to load resource: 404`

**症状**: 控制台出现 `Failed to load resource: 404`。

**通常无害**: 多半是 favicon 或某个 telemetry 端点。如果 lint/validate/inspect 都通过,可以忽略。如果影响渲染,看 inspect 输出定位。

## 3. `inspect` 必修复

### Layout issues(文本溢出/裁切)

**症状**: `inspect` 报 "Text extends outside nearest container" 或 "Text clipped by fixed box"。

**修复**:
- 给容器加 `max-width` 让文本自然换行
- 用 `window.__hyperframes.fitTextFontSize(text, { maxWidth, fontFamily, fontWeight })` 动态缩字
- 不要用 `<br>` 强制换行(它按字符数断行不按视觉宽度)
- 长代码用 `display: block; word-break: break-all;` 或预拆行

### 0 layout issues 但视觉错位

**症状**: inspect 通过,但渲染出来元素挤在左上角。

**根因**: 根 `<div data-composition-id>` 或中间 wrapper 没有显式 height,flex/`height:100%` 容器坍塌到 0,内容堆在 (0,0)。lint/inspect 不报。

**修复**: 在根上写死 `position: relative; width: 1920px; height: 1080px; overflow: hidden`,不要依赖 flex `height: 100%` 链路传递。

## 4. `render` 阶段

### `HeadlessExperimental.beginFrame is unavailable`

**症状**: `doctor` 报"using system Chrome ... falls back to screenshot mode"。

**完全无害**。HyperFrames 检测到这不是 chrome-headless-shell,自动降级到普通截图模式,渲染会变慢但产物完全正常。**不要让 AI 看到这条就以为环境坏了**。

### `GSAP target not found` 警告

**症状**: 浏览器控制台反复出现 `GSAP target  not found`(selector 是空字符串)。

**根因**: 代码里有 `tl.from("", ...)` 或 `tl.to(undefined, ...)`。检查循环生成 tween 时 selector 模板字符串拼接是否漏了变量。

### Docker unavailable

**症状**: `doctor` 报 `✗ Docker Not found`。

**影响**: `--docker` 标志不可用(无法做 byte-identical 渲染),但普通 `render` 正常。系统 Chromium 一样能渲染。**不要让 AI 看到这条就 stop**。

## 5. 快速诊断表

| 现象 | 第一动作 |
|---|---|
| render 后画面空 | 检查 `class="clip"` 是否漏了 |
| render 后字体变了 | 检查 `font-family` 是否在白名单 |
| render 后画面挤在左上角 | 检查根 `data-composition-id` 元素是否设了 `width/height: 1920/1080px` |
| 文字超出卡片 | `inspect` 给精确 selector,用 `fitTextFontSize` 或 `max-width` 修 |
| 进度条没动 | 检查 `.top-bar::after` 的 `width: 0% → 100%` tween 是否在 timeline 上 |
| 声音没有 | 这套流程默认无音频,要 TTS/旁白走 `hyperframes-media` 的 `audio.mjs` |
