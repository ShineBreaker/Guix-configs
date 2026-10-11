# 第三方 SVG/PNG 资产内嵌与裁切（librsvg 实测）

适用：把官方 SVG/PNG 嵌进自制 SVG，且只需要其中一部分（如只要图形部、不含字标）。

## 决策顺序

1. **默认**：整文件 `<image href="data:image/svg+xml;base64,...">` + `<clipPath>` 裁窗口。
2. 同一资产多处复用，或交付物要能单独分发资产：先落盘到产出目录，`<image href="assets/x.svg">` 相对引用（打包时一起带上）。
3. 只有资产是单色 flat 且结构极简单，才考虑抽 path 重组——否则别碰。
4. **clipPath 路线调了 2 轮还调不准时，改走位图**：`rsvg-convert -w <高清> -b none src.svg -o asset.png` 把官方 SVG 渲成透明 PNG，裁净透明边后按 PNG 嵌入。矢量让位给确定性——位图裁切窗只有「缩放比」一个变量，没有嵌套 svg、preserveAspectRatio、clip 三者互相咬合的变量。贴纸最终交付物本来就要 ≥3000px PNG，这一步不损失。

data URI 的 SVG 保留自己的 `<defs>` 与渐变，不需要把渐变外泄到外层文档。

## 算裁切窗

1. 渲染原资产，量内容 bbox：
   `rsvg-convert -w 400 -b none src.svg -o probe.png`，PIL 逐像素按目标色（或 alpha>10）统计 bbox。
2. 内容占比 = `bbox / 画布尺寸`。想要的内容高度 `h_target` → `image` 高度 `H = h_target / 占比高`。
3. `image` 的 x/y 反算：`y_img = y_clip_top - H * (bbox_top / 画布高)`，x 同理。
4. **`image` 的 width/height 必须与原资产画布等纵横比**；`preserveAspectRatio="none"` 会直接拉扁，`meet` 只在留空时保形，别指望它救非等比例框。
5. clip 矩形贴到目标位置；clip 与被裁资产都画在底色之后、文字之前。

PNG 资产先裁透明边再嵌入：`box = img.getbbox(); img.crop(box)`。否则 image 框里的透明 padding 会把内容顶出预期位置，出现「元素只露一个尖」的假象。

**裁完必须复查内容行分布**：`getbbox()` 按 alpha>0 取框，仍可能圈进稀疏的透明行或抗锯齿残点，让内容实际占比比框小一截——image 框按框缩放后，内容顶部或底部又被切掉。裁完按行统计 alpha 非零像素数，确认内容连续铺满上下沿：

```python
for y in range(h):
    row = [img.getpixel((x, y))[3] for x in range(0, w, w // 12)]
    print(y, row)   # 上下沿应全程 255，中间允许 0
```

## 验证元素真的画全了（别问视觉模型）

合成图渲出来问 vision「logo 完整吗」在缩小图上不可靠：被裁掉大半的元素会被判成「完整」，把后续几何微调全建在错误结论上。改用程序化确认：

```python
from PIL import Image
im = Image.open(out).convert("RGB")
w, h = im.size
# 1. 单色像素量内容 bbox（阈值收紧到只命中目标色）
pts = [(x, y) for y in range(h) for x in range(w)
       if (lambda p: p[0] > 220 and p[1] > 150 and p[2] < 110)(im.getpixel((x, y)))]
print("bbox:", min(x for x, _ in pts), min(y for _, y in pts),
      max(x for x, _ in pts), max(y for _, y in pts), len(pts))
# 2. 逐行 ASCII 剖面看轮廓（有没有被切断一眼可辨）
for y in range(y0, y1, step):
    print(y, "".join("#" if hit((x, y)) else "." for x in range(x0, x1, 6)))
```

两个信号说明元素被裁：bbox 顶/底沿贴着你设的 clip 矩形边界；ASCII 剖面在边缘行突然变窄或断成两截。判「真没画」还是「被裁」：把 image 框临时放大到远超 clip 区，若 bbox 跟着变大说明画了只是被裁，若仍是空说明根本没渲染。

## 已实测行为

- 外层 SVG 内嵌带 `viewBox` 的内层 `<svg>`：单独渲染 OK，放进大合成后出现裁切/变形 —— 不要依赖。
- 无 `viewBox` 的 Inkscape SVG：path 坐标带 layer `translate(0,-752.36)` 一类变换，脱离文档抽取后位置全错；`inkscape:` / `sodipodi:` 前缀属性在未声明命名空间时让 rsvg 报 XML parse error。清属性时正则必须用 `[\w-]+` 匹配带连字符的属性名（`\w` 不匹配 `-`，会漏清 `inkscape:connector-curvature`）。
- 把官方 SVG 的渐变 `linearGradient` 重写成两色 stop（金 `#ffb638 → #f0ae26` 一类）可以去掉对 base gradient 的 `xlink:href` 依赖，但这是抽 path 路线才需要的步骤；走 `<image>` 整文件嵌入时完全不用管。

## 定位元素的颜色阈值

在合成图里按颜色找元素时，先列出图中所有可能撞色的色块（语法高亮、邻近品牌色），把阈值收紧到只命中目标；量完用像素计数与预期坐标对一遍。宽松阈值量出的 bbox 会把后续所有几何微调带到错位置上。
