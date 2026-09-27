---
name: zh-tech-doc-style-guide
description: "中文技术文档写作风格与标点规范查询手册。"
version: 0.1.0
author: Hermes
metadata:
  hermes:
    tags: [Chinese, Technical-Writing, Style-Guide, Punctuation, Documentation]
---

# 中文技术文档写作风格指南

蒸馏自 yikeke/zh-style-guide（readthedocs 在线版 + PDF v0.1，2025-01-06，50 页）。覆盖语言风格、结构样式、内容元素、标点符号、名称与命名、拼写与语法六大块。这是一本**查询手册**，不是通读教材：写作时按问题定位到对应章节，而不是逐条背诵。上游是社区综合规范，非权威标准。

## 核心心智模型

1. **规则强度分级（RFC2119 中文映射）**——全书每条规则的语义由关键词决定，读到任何条目先分辨强度：
   - 强制/必须/务必/只能 → MUST：绝对要求
   - 禁止/不能/不要 → MUST NOT：绝对禁止
   - 应/应当/应该/建议/推荐 → SHOULD：一般应做，知悉后果可选不做
   - 不应当/不应该/不建议/不推荐 → SHOULD NOT：一般不应做，知悉后果可选做
   - 可以/可选 → MAY：任选
2. **上游定位**：素材为各家中文文案风格指南的综合，业界无定论的争议点以「建议」形式给出，不当成硬规则执行。
3. **适用范围**：中文文档作者（研发、tech writer）、审校争议裁决、软件界面与帮助文档参考。
4. **使用姿势**：先浏览目录建立范围感，再按实际问题回查；写完后用 `拼写与语法` 章的工具清单过一遍。

## 快速定位

| 要解决的问题 | 加载文件 |
| --- | --- |
| 语气是「对话式」还是「客观」、该不该用「您」、怎么做到通俗易懂 | `references/language-style.md` |
| 标题层级、段落长度、句子结构、要不要写目录 | `references/structure.md` |
| 中英文间空格、列表/表格/图片/代码块怎么写、数字与单位格式 | `references/content-elements.md` |
| 链接文案、引用格式、缩略语首现、交叉引用 | `references/links-and-refs.md` |
| 全角半角、中英混排标点、顿号逗号、书名号用法 | `references/punctuation.md` |
| 文件名、产品名、变量名、术语一致性 | `references/naming.md` |
| 拼写检查、语法纠错、文档质量工具链 | `references/spelling-grammar.md` |
| 成稿前逐条自检、常见错误对照 | `references/cheatsheet.md` |

按需加载：`skill_view(name="zh-tech-doc-style-guide", file_path="references/<file>")`。reference 文件不占上下文，直到问题真正需要它。

## Prerequisites

- 无外部依赖。纯规范查询。
- 上游源（用于核对最新版）：https://zh-style-guide.readthedocs.io/zh-cn/latest/ ，仓库 github.com/yikeke/zh-style-guide。
- 若本地持有该 PDF：注意 PDF 由 LaTeX 生成、可能为扫描件（50 页），优先用在线 HTML 版取正文，避免 OCR。
- **机械规则已有工具落地**：`orgfmt`（agenote 包，`~/Projects/agenote/agenote/src/agenote/orgfmt.py` 的 `_zh_style` 阶段）自动修复 8 项——全角空格、全角标点旁空格、中英文间距、破折号、英文省略号、连续感叹号、序数词顿号、数值与单位间距；语义级规则（的/地/得、顿号误用、繁体用语、不规范缩略语）只报不改。`orgfmt --check <file>` 的退出码即问题数，可当 lint 门禁；Markdown 与 Org 两种格式共用同一份规则。语义级项仍靠本 skill 人工裁决。

## How to Run

1. 明确问题属于哪一维度（语气 / 结构 / 元素 / 标点 / 命名 / 语法）。
2. 按「快速定位」表 `skill_view` 加载对应 reference。
3. 用文件里的规则改写或裁决；规则带 RFC2119 强度词，强制的必须改，建议的可说明后保留。
4. 交付前过一遍 `references/cheatsheet.md` 的自检清单。

## Quick Reference

| 维度 | 一句话内核 |
| --- | --- |
| 语言风格 | 对话式、客观礼貌、简洁清晰、通俗易懂、用户导向、用词恰当 |
| 文档结构样式 | 标题、段落、句子、目录 |
| 文档内容元素 | 空白符号、列表、表格、图形和图片、注意和说明、代码块和代码注释、链接、引用、缩略语、数字、单位符号 |
| 标点符号 | 常用中文标点符号、中文标点使用、中英文混用时标点符号用法 |
| 名称与命名 | 文件命名、产品命名、名称使用 |
| 拼写与语法 | 拼写、语法、文档质量检查工具 |

## Pitfalls

- 上游明确「只提供参考规范，不提供权威标准」——不要把建议级规则当成硬性标准驳回别人的稿子。
- 规范持续更新，线上 latest 版可能比本地 PDF 新；涉及争议条款先回上游核对。
- 本 skill 是蒸馏笔记，不是原文转载；引用具体条款给用户时以上游链接为准。

## Verification

写完中文技术文档后，用 `skill_view` 加载 `references/cheatsheet.md`，逐条过自检清单；重点项（中英文空格、全角标点、标题层级）应能在交付稿中直接验证。
