---
name: pdf-translation
description: Incremental, resume-able PDF → structured Markdown translation workflow. Use when the user wants a long PDF (book, manual, cookbook, spec) translated into Markdown while preserving translation progress across sessions — split into slices, track translated/untranslated state in a manifest, assemble the final doc on demand. Covers PyMuPDF extraction that preserves code indentation and restores heading hierarchy from font sizes.
---

# PDF → Markdown 增量翻译工作流

当用户要把一整本长 PDF（书、手册、cookbook、规范）翻译成中文/其他语言的 Markdown，
且希望**分批推进、可随时续译、不丢进度**时使用本 skill。

## 触发信号
- 用户要求「翻译这篇 PDF / 这本书 / 这个手册」。
- 用户明确说「分部分翻译」「先译一章」「用文件夹区分已译/未译」「保留翻译状态」。
- 文档过长、一次译完不现实，需要可恢复的状态。

## 核心工作流

### 0. 提取工具选择（重要）
- 在 **Guix Home** 环境里，**优先用 `guix search` + `guix install`** 提供工具，而不是 `pip install`
  （用户偏好：工具尽量走 guix channel，由用户来装）。
- 本任务验证可用的包：`python-pymupdf`（提供 `fitz`，按字号定位标题 + 按坐标裁剪保留缩进）。
- 其它候选：`poppler`(提供 `pdftotext`，最轻但丢失布局)、`python-pdfminer-six`、`python-pikepdf`。

### 1. 用 PyMuPDF 提取（详见 references/pymupdf-extraction.md）
- **只用 `get_text("dict")` 来检测标题层级**：收集每个 block 的最大字号，按字号聚类
  （例：17.2pt=章/H1、14.3pt=节/H2、13.1pt=小节/H3、9~10.9pt=正文）。
- **正文切莫用 dict 输出**——dict 会把代码块所有 span 压成一行，**代码缩进全丢**。
  正文改用 `get_text("text", clip=rect)`，按标题的 (page, y0/y1) 边界做坐标裁剪提取，
  这样**代码缩进、段落断点、REPL 标记都保住**。
- 用 `unicodedata.normalize("NFKC", ...)` 展开连字（ﬁ/ﬂ/…）。

### 2. 搭建工作区（状态可恢复的关键）
```
<workdir>/
├── manifest.json      # 权威状态索引：每个切片的 id/title/pages/level/status
├── glossary.md        # 术语表（首现中文+英文，后续仅中文）
├── README.md          # 工作区说明
├── assemble.py        # 按 manifest 顺序拼接 translated/*.zh.md
├── source/            # 原文切片 .en.md（只读参考，永不改）
├── untranslated/      # 待译切片 .en.md（译完移走）
├── translated/        # 已译切片 .zh.md
└── archive/           # 已译原文件 .en.md（对照归档）
```
- 每个切片文件**首行是 HTML 注释头**，含 `id / title / pages / level / status=pending`。
- 切片粒度：H1/H2 开新切片；H3 子节留在所属 H2 切片内（译为 `###`）。

### 0.5 续译前先对账（关键，防状态漂移）
每一轮会话**开头、翻译任何新切片之前**，必须先做一次状态对账。原因：上一轮会话
若在「写完 `translated/<id>.zh.md`」之后、「更新 manifest + 把原文移入 archive/」之前
中断，会留下**孤儿译文**——`translated/` 已有 `.zh.md`，但 `manifest.json` 仍标 `pending`、
`untranslated/` 原文未归档。不先对账就继续往下译，会造成重复劳动、进度统计失真。

对账逻辑（对每个 chunk）：
- `translated/<id>.zh.md` 存在 且 `manifest.status == pending` → 这是漏登记的已完成译文。
  把 `status` 改为 `translated`、`translated` 字段填 `translated/<id>.zh.md`，并把
  `untranslated/<id>.en.md` 移入 `archive/`（archive 已有同名则直接删 untranslated 副本）。
- `status == translated` 但 `translated/<id>.zh.md` 缺失 / `untranslated/` 仍留原文 → 状态
  与实际不符，需人工核对。

可直接跑 `scripts/reconcile_manifest.py`（默认只报告，加 `--repair` 才改）。对账后
跑一次 `assemble.py` 确认拼接无误。

### 3 推进单一切片的标准流程
1. 从 `untranslated/` 取 `X.en.md`，对照 `source/X.en.md`（内容相同）。
2. 译出 `X.zh.md` 写入 `translated/`（保留首行注释头，把 `status` 改为 `translated`）。
3. 把对应 `.en.md` 从 `untranslated/` 移入 `archive/`。
4. 更新 `manifest.json` 该切片的 `status` 与 `translated` 路径。
5. 跑 `assemble.py` 重新生成单一中文稿（如 `~/Documents/guix-cookbook.zh.md`）。

### 4. 先译「样板章」再放量
- 先把**第 1 章**（或任一短章）译完，交用户确认风格，再全量推进。
- 这能避免 35 万字译完才发现风格不对、整体返工。

## 译文 Markdown 约定
- **代码 / 命令 / 包名 / 标识符 / 变量**：一律保留原文。
- **技术术语**：首现「中文（English）」，后续仅中文（例：S-表达式（s-expression）、过程（procedure）、G-表达式（gexp））。
- **人名**：保留原名（Christine Lemmer-Webber）。**手册/书名**：保留英文并加《》。
- **代码内注释**：译为中文便于通读（若用户想保留英文注释，统一回退）。
- **标题层级**：严格跟随原文字号档（`#`=章、`##`=节、`###`=小节）。
- **REPL 标记** `⇒`(求值结果) / `⊣`(打印输出) / `` ` ``(准引用) / `,`(取消引用) 按原样保留。
- 原文 PDF 的 Unicode 错位（如 `git rebase –interactive` 用长破折号）按语义修正为正确形式（`--`）。

## 脚本与模板
- `references/pymupdf-extraction.md` —— 提取技术细节 + dict 压平缩进的坑。
- `scripts/split.py` —— 可复跑的切片器（字号定标题 + 坐标裁剪正文），阈值按具体 PDF 调整。
- `scripts/reconcile_manifest.py` —— 续译前对账：比对 manifest 状态与实际文件，报告（或
  `--repair`）孤儿译文（写了 .zh.md 但 manifest 仍 pending、原文未归档）。
- `templates/manifest.json` —— 状态索引结构样例。

## Pitfalls（踩过的坑）
- **dict 模式把所有 span 拼成一行 → 代码缩进丢失**。正文必须用坐标裁剪 `text+clip`。
- **概念索引 / 附录页会被误判为标题**：单字母 A/B/C 小标题、或 "2FA" 这类索引条目会被
  字号识别成 H1。过滤规则：索引页（page>=某阈值）除 "Concept Index" 本身外不识别为标题；
  长度≤2 的纯字母块跳过。
- **同页多个标题**：切片结束边界取「下一个标题的 (page, y0)」，裁剪区间 [本标题底, 下一标题顶)。
- **末片无下一标题**：区间到文档末页，整页提取（`clip=None`），避免 `nxt_ytop=None` 报错。
- **不要**在 Guix Home 环境默认 `pip install`；先 `guix search` 让用户用 guix 装。
- **不要**把中间切片的状态写在内存/对话里——状态只进 `manifest.json`，否则跨会话丢失。
- **提取噪声要清理，不要逐字照抄 PDF 杂质**。PyMuPDF 切片并非完美，原文 `.en.md` 常见三类
  污染，译文时按上游官方英文版语义修正：① 章节页眉 `Chapter N: Title  Page` 混进正文
  （直接删）；② 连字/大小写粘连 Mojibake，如 `KimsuﬁServer`（`ﬁ` 连字撑成大写 i）、
  `netboot tab` 词间空格丢失成 `netboottab`；③ 缺字/断句，如 "install guix from see
  Section …" 应为 "install Guix (see Section …)"。译文追求通顺正确，不为保留噪声牺牲质量。
