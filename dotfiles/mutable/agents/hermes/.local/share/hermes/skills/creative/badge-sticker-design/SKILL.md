---
name: badge-sticker-design
description: "Use when 仿参考设计做贴纸/徽章，或从零设计一枚。反推设计令牌、内嵌官方 logo、交付高清 SVG+PNG。"
version: 1.0.0
license: MIT
author: BrokenShine
metadata:
  hermes:
    tags: [sticker, badge, design-replication, svg, print, branding]
    related_skills: [brand-logo-assets, ai-image-asset-pipeline]
---

# 贴纸/徽章设计（Badge & Sticker Design）

用户给来一份参考设计（图片 / SVG / zip），要「参考它的设计做一个 X」；或要从零设计一枚贴纸徽章。产出：矢量 SVG 源 + 高清透明 PNG，附带设计说明与授权口径。

## When to Use

- 用户发参考图/设计包说「参考这个设计做一个 <别的品牌/词>」
- 用户要定制贴纸/徽章（打印级清晰度）
- 已有一组设计令牌，要批量出变体（换词、换色、换 logo、圆角/直角两版）

## 硬规则

- **只内嵌官方品牌标志，绝不手画重制**（同 brand-logo-assets 的来源阶梯）。官方 SVG 整文件内嵌，不重描 path。
- **交付双格式**：矢量 SVG（印刷厂/改尺寸用）+ ≥3000px 透明 PNG（定制贴纸直接可用）。1024px 只够联系表预览，不够定制打印。
- **透明底**：`rsvg-convert -b none`（等价 `-b transparent`）。白底交付等于自带白边。
- 设计令牌（色值、字号比、间距）从参考图的**像素**测，不靠目测类比；参考图自带 SVG 时优先读它的 `path` 与 `fill`，那是最准的几何。
- 参考图提供多个变体时（如圆角/直角）**两个都交付**，别只出一个让用户猜。

## 1. 反推参考设计

1. 解包：`unzip -o <ref>.zip -d <dir>`，忽略 `__MACOSX/`（AppleDouble 垃圾）。
2. **参考 SVG 里的位图资产要抽出来看**：位图以 `<image ... xlink:href="data:image/png;base64,...">` 内嵌，用正则抽出 base64 落盘才能判断每张是「截图 / logo / 纹理」。SVG 本体只含几何形状。
3. 量设计令牌（PIL；无 numpy 也能做）：
   - 内容范围：`getbbox()`，或逐像素非透明/非背景统计
   - 主色：`resize((8,8))` 或全图像素 Counter 取众数（编辑器底色、品牌蓝这类一问一个准）
   - 元素位置：按颜色阈值找 bbox；**阈值要收紧并交叉验证**（见坑）
   - 文案层级：量每个词形的 bbox 高宽，得到「大字:小字」比例，复刻时照抄比例
4. **文件名后缀的含义用像素差反推**：参考图常成对提供（`with rc` / `without rc`）。逐像素 diff 两版，差异 bbox 与行分布直接指出变量是什么——比按缩写猜语义（rc ≠ release candidate，这次是 rounded corners）可靠。

## 2. 组装变体

- 把测得的元素 bbox 归一成参考画布的单位（如 388×428），在新 SVG 里用同一 `viewBox` 复写，等比放大即高清。
- 背景分区（顶条 / 主体色块 / 圆角）按参考图的分区高度复现；分区之间的接缝行用单像素采样确认。
- 官方 logo 的嵌入与裁切见 `references/svg-embedding.md`，那是本技能最易翻车的一步。
- 字体：优先系统可用字体（`fc-list` 确认，DejaVu Sans Bold 是稳妥默认），并在 README 注明，便于用户换字体重渲染。

## 3. 交付形状

```
<name>/
├── <name>.svg          # 主版本（参考图的默认变体）
├── <name>-plain.svg   # 次要变体（直角/无圆角等）
├── <name>-8x.png      # ~3100px 透明 PNG，定制贴纸用
├── <name>.png         # ~1550px 预览
└── README.md          # 设计说明 + 授权口径 + 改尺寸命令
```

- **授权口径写进 README**：内嵌的官方标志版权归原项目，衍生整体按原标志许可分发（如 Guix artwork 是 CC BY-SA 4.0，别写成「我拥有」）。
- README 给一条改尺寸命令：`rsvg-convert -w <宽> -b none in.svg -o out.png`。
- 交付时把高清 PNG 直接发给用户（QQ 场景用 `MEDIA:/abs/path`）。

## 坑

- **librsvg 里「外层 SVG 嵌带 viewBox 的内层 `<svg>`」行为不一致**：同样的嵌套单独渲染正常，放进大合成图就被裁/变形。要裁第三方资产，用 `<image href="data:...">` + `<clipPath>`，别用嵌套 svg。
- **无 viewBox 的官方 SVG 不要抽 path 重组**：path 坐标带 layer `translate`，脱离文档抽取后不是全黑就是出界；`inkscape:` / `sodipodi:` 前缀属性在未声明命名空间时让 rsvg 直接报 XML parse error。整文件内嵌最稳。
- **`<image>` 的 width/height 是裁切窗不是装饰**：把 300×300 资产拉成非等比例框会压扁内容；先渲染原图量内容占比，再反算 image 尺寸与 clip 矩形（算法见 references）。
- **按颜色定位元素必须用紧阈值**：合成图里语法高亮的橙色条带会命中宽松的「金色」判定，量出假 bbox，随后所有几何微调都建立在错位置上。量完用像素计数与预期坐标对一遍。
- PIL `getdata()` 已废弃且**不支持切片**（`getdata()[i:j]` 直接 TypeError）：用 `get_flattened_data()` 或先 `list()`。
- 中稿发现「元素看不见」时，先区分是**真没画**还是**颜色判定把友军算进来了**——用单色隔离图复测，别反复调几何。

## 参考

- `references/svg-embedding.md` — 第三方 SVG/PNG 资产内嵌与裁切（librsvg 实测行为 + 裁切窗算法）
- brand-logo-assets — 官方 logo 的来源阶梯、单色修正、归一化与验证
