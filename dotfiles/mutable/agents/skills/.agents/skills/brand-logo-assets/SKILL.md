---
name: brand-logo-assets
description: "为贴纸或设计收集官方品牌 logo 素材（来源、授权、规格与内嵌）。触发：找官方 logo / 收集品牌素材 / 贴纸设计需要 logo——任一出现即调用。"
version: 1.0.0
license: MIT
author: BrokenShine
metadata:
  hermes:
    tags: [brand-assets, logos, svg, print, stickers, simple-icons, asset-library]
    related_skills: [ai-image-asset-pipeline, web-data-harvesting]
---

# 品牌 Logo 资产库（Brand Logo Assets）

把「某个工具链/品牌集合的官方 logo」抓成一份能直接交付的素材库：贴纸打印、幻灯片、周边。产出是**每项一个目录 + 统一尺寸 PNG + 来源 meta + 索引 README + 联系表拼版 + 打包**。

## When to Use

- 用户要某种展示品（笔记本贴纸、幻灯片、周边）的品牌 logo 合集
- 用户说「把我用的工具/AI 模型/技术栈的 logo 收集一下，方便打印/定制」
- 已有一批 logo 来源散落，需要统一成可交付的素材库

## 硬规则（每次都适用）

- **只取官方标志，绝不手画重制**。来源优先级见下；官方源确实没有时留空占位并在索引里说明，不用近似图冒充。
- **官方源本身单色的品牌保持单色**（Rust / Bun / Next.js / Markdown / Anthropic 官方深色 / Ollama 黑白源…）。编造颜色是对品牌的不忠实；需要醒目就**另出一个上色变体文件**（如 `sticker-color.png`），不改原图。
- **交付前按实际底色判断可见性**：奶油底/白底 logo 贴在深色笔记本上等于没有，交付前换成深色版或补一版。
- **颜色看像素，不看 HTML**：SVG 里没有 `fill` ≠ 图是黑的，但渲染出来大概率就是黑的——必须落到像素验证。
- **贴纸/这类「展示技术倾向」的集合只收工具属性强的项**：AI 模型/harness、编辑器/终端、系统桌面基础设施、技术栈。通讯社交 / 游戏 / 设计类**先问一句**去留（一次问全，不逐项问）。

## 1. 产出形状

```
<库>/
├── README.md            # 索引表：名称 / 品牌色 / 来源 URL + 打印说明
├── preview-<类>.png     # 每类一张缩略联系表（挑图用）
├── <分类>/<名称>/
│   ├── icon.svg|png|ico # 原始素材（官方源原样保留）
│   ├── sticker-1024.png # 统一 1024×1024 透明底
│   └── meta.json        # source / brand_color / files
└── <库>.tar.gz          # 交付包
```

每项 `meta.json` 至少带 `source`（可回溯 URL 或本地绝对路径）、`brand_color`、`files`。品牌色既是配色参考，也是 colorize 的输入。

## 2. 来源阶梯（从最权威到最兜底）

| 档 | 来源 | 命令 / URL |
| --- | --- | --- |
| 1 | **本机已安装资产** | `~/.local/share/icons/hicolor/scalable/apps/<app>.svg`、`~/.guix-home/profile/share/icons/`、本地源码树 `public/logo/`、`$APP_HOME/assets/*.svg`。自制/未发布工具的 logo 常只在这里 |
| 2 | **官方仓库资产树** | `gh api repos/<owner>/<repo>/git/trees/<branch>?recursive=1 --jq '.tree[].path' \| grep -iE 'logo\|icon\|\.svg'` → 再取 `raw.githubusercontent.com/...` 实体 |
| 3 | **simple-icons**（官方授权品牌标志合集） | `https://cdn.jsdelivr.net/npm/simple-icons@latest/icons/<slug>.svg`；slug 与 hex 索引：`https://data.jsdelivr.com/v1/packages/npm/simple-icons@latest?structure=flat`，或包内 `_data/simple-icons.json` |
| 4 | **Wikimedia Commons**（simple-icons 未收录的） | `https://commons.wikimedia.org/wiki/Special:FilePath/<File%20Name>.svg` |
| 5 | **官网 favicon**（最后兜底） | 先扒官网首页 HTML 找真实 logo 资产路径，别只下 `/favicon.ico` |

无效/会耗时间的路径：`cdn.simpleicons.org` 对非浏览器 Referer 返 403；未认证 GitHub REST API 会限流（用本机 `gh` CLI 借 token）；jsdelivr 的 gh 包超过 50 MB 直接 403（改走档 2 的 `gh api` 资产树）。

## 3. 抓取与上色

1. **先批量探测可达性再统一下载**：并发 8–12 个 HEAD/小 GET，把不可达项先换成下一档来源；不要边下边换源、不要下完才发现整类不可用。
2. **按文件头判定真身**：SVG 头必须是 `<svg`，PNG 必须是 `\x89PNG`，ICO 是 `\x00\x00\x01\x00`。官网 404 兜底页常返回 200 + HTML，靠扩展名判型会中招。
3. **simple-icons 单色修正**：这些 SVG 无 `fill` 属性，渲染器按默认纯黑出图。把 meta 里的品牌 hex 写成**根元素属性**（`fill` 可继承，librsvg 一定吃）：
   `re.sub(r"<svg\b", f'<svg fill="#{hex}"', t, count=1)`
   CSS `<style>{svg{fill:...}}</style>` 注入在 rsvg-convert / librsvg 下**不生效**，别走那条路。
4. 已是彩色的官方 SVG（自带 `fill=`/`style="fill:`/`fill:` 的）**原样不动**，只给无色的注入。

## 4. 归一化（打印/贴纸）

- 统一 1024×1024 透明画布；40–60 mm 贴纸约 430–650 dpi，够清晰。
- SVG：`rsvg-convert -w 1024 -h 1024 --keep-aspect-ratio -b transparent icon.svg -o sticker-1024.png`
- 位图：PIL `convert("RGBA")` → `thumbnail((1024,1024), LANCZOS)` → 贴透明画布居中。ICO 用 PIL 直接 open 后 thumbnail；webp 同样 convert RGBA 后存 PNG。
- **横向 logo**：先 `getbbox()` 裁掉透明边，再把内容缩到画布的 60–92% 高度居中——直接铺满会让横向标志上下各空一大条。
- 改过分类名/删过项之后重跑联系表，并**删掉上轮遗留的旧分类拼版图**。

## 5. 验证（不验证等于没做）

**程序化**（`scripts/build_logo_library.py` 内置同款检查）：

- 1024×1024；alpha 通道非空像素 > 200；`meta.json` 有 source；`category` 字段与所在目录一致。
- 主导色统计判彩色/单色：对 alpha>200 的像素取众数，`r==g==b` 记单色，与预期"官方单色"清单逐项对照。
- **像素统计按 RGBA 四字节对解析**（PIL `getdata()` 或 `bytes[i:i+4]`）；把 RGBA 当 RGB 逐字节解析会得出虚假的"全部单色"结论。

**视觉**：每类出一张联系表拼版，逐格过一遍，专抓空白、纯黑块、糊掉的 favicon 放大、以及**"其实是界面截图不是 logo"的冒牌货**（官方 splash/宣传图常被误当标志——拿到就先判断，是截图就改名 `ui-preview.png` 并补真 logo）。

## 6. 坑

- **批量统计报告先核对落盘位置再信**：输出根路径在上轮改动后没同步，产物会静默写进废弃目录，而统计照常输出"全部成功"。改动输出路径后，先 `stat` 比对源文件与产物的 mtime 顺序，再解读任何"全黑/全彩"类汇总。复用上轮遗留脚本时同样先 search_files 它的 `ROOT`/输出常量，别默认它指向当前工作目录。
- **favicon 只有 32 px**：放大必糊。扒官网 HTML 里的真实 logo 资产（形如 `/_next/image?url=%2Fassets%2Flogo%2F*.webp`）替换。
- **官方 splash ≠ logo**：站点/仓库里的终端截图或宣传图不等于品牌标志，交付前用视觉确认图形内容。
- **版权口径写进 README**：品牌 logo 归各自所有者；个人贴纸属个人用途，商用前自行核对品牌规范。

## 参考

- `references/logo-sources.md` — 各类工具的可靠源与探测结论（含失效路径）
- `scripts/build_logo_library.py` — 抓取 + 上色 + 归一化 + 验证一体脚本（读 manifest JSON）
- `templates/manifest.example.json` — manifest 形状示例
- badge-sticker-design — 把单个官方 logo 嵌进参考设计做贴纸/徽章（含裁切窗算法）

## 源码树里的假 logo

在包源码 / checkout / `misc/logo` 一类目录翻到的 SVG，**先看同目录 LICENSE.txt 再当官方标志用**：上游仓库里嵌的常是别的项目的图（Guix checkout 的 `misc/logo` 实际是 Godot Engine Logo）。
