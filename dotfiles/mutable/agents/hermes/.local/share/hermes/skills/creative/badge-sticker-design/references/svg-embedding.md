# 第三方 SVG/PNG 资产内嵌与裁切（librsvg 实测）

适用：把官方 SVG/PNG 嵌进自制 SVG，且只需要其中一部分（如只要图形部、不含字标）。

## 决策顺序

1. **默认**：整文件 `<image href="data:image/svg+xml;base64,...">` + `<clipPath>` 裁窗口。
2. 同一资产多处复用，或交付物要能单独分发资产：先落盘到产出目录，`<image href="assets/x.svg">` 相对引用（打包时一起带上）。
3. 只有资产是单色 flat 且结构极简单，才考虑抽 path 重组——否则别碰。

data URI 的 SVG 保留自己的 `<defs>` 与渐变，不需要把渐变外泄到外层文档。

## 算裁切窗

1. 渲染原资产，量内容 bbox：
   `rsvg-convert -w 400 -b none src.svg -o probe.png`，PIL 逐像素按目标色（或 alpha>10）统计 bbox。
2. 内容占比 = `bbox / 画布尺寸`。想要的内容高度 `h_target` → `image` 高度 `H = h_target / 占比高`。
3. `image` 的 x/y 反算：`y_img = y_clip_top - H * (bbox_top / 画布高)`，x 同理。
4. **`image` 的 width/height 必须与原资产画布等纵横比**；`preserveAspectRatio="none"` 会直接拉扁，`meet` 只在留空时保形，别指望它救非等比例框。
5. clip 矩形贴到目标位置；clip 与被裁资产都画在底色之后、文字之前。

PNG 资产先裁透明边再嵌入：`box = img.getbbox(); img.crop(box)`。否则 image 框里的透明 padding 会把内容顶出预期位置，出现「元素只露一个尖」的假象。

## 已实测行为

- 外层 SVG 内嵌带 `viewBox` 的内层 `<svg>`：单独渲染 OK，放进大合成后出现裁切/变形 —— 不要依赖。
- 无 `viewBox` 的 Inkscape SVG：path 坐标带 layer `translate(0,-752.36)` 一类变换，脱离文档抽取后位置全错；`inkscape:` / `sodipodi:` 前缀属性在未声明命名空间时让 rsvg 报 XML parse error。清属性时正则必须用 `[\w-]+` 匹配带连字符的属性名（`\w` 不匹配 `-`，会漏清 `inkscape:connector-curvature`）。
- 把官方 SVG 的渐变 `linearGradient` 重写成两色 stop（金 `#ffb638 → #f0ae26` 一类）可以去掉对 base gradient 的 `xlink:href` 依赖，但这是抽 path 路线才需要的步骤；走 `<image>` 整文件嵌入时完全不用管。

## 定位元素的颜色阈值

在合成图里按颜色找元素时，先列出图中所有可能撞色的色块（语法高亮、邻近品牌色），把阈值收紧到只命中目标；量完用像素计数与预期坐标对一遍。宽松阈值量出的 bbox 会把后续所有几何微调带到错位置上。
