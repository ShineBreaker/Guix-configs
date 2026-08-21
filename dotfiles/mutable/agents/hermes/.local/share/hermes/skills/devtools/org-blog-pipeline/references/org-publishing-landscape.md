# Org 博客发布工具生态全景（2026-08 调研数据）

> 数据来源：GitHub API（仓库元数据/commits/tags）、npm registry、各项目官方文档。
> 调研日期：2026-08-09。本文档定期需要更新——工具维护状态会变化。

## 转换路线（Org → Markdown → SSG）

### ox-hugo

| 维度 | 详情 |
|---|---|
| 仓库 | `kaushalmodi/ox-hugo` |
| npm/npm | MELPA (`package-install ox-hugo`) |
| Stars | 946 |
| 最后推送 | 2025-12-06 |
| 维护 | 🟢 活跃 |
| 原理 | Emacs 把 Org 导出成 Hugo 兼容 Markdown + front matter（TOML 或 YAML） |
| 模式 | one-post-per-subtree（推荐）/ one-post-per-file |
| 主题兼容 | 任何 Hugo 主题（输出标准 Hugo Markdown） |

**front matter 自动映射**：subtree 标题 → `title`、CLOSED/EXPORT_DATE → `date`、tags `:a:b:` → `tags`、`:@c:` → `categories`、TODO 状态 → `draft`

**org-roam 共存已知问题**（均已有社区解决方案）：
- `[[id:...]]` 链接路径错乱 → strip-directory advice
- CREATED 属性不映射 date → `org-export-get-environment` advice
- `#+filetags` 不被 ox-hugo 识别 → 需转换或批量脚本
- backlinks 无原生支持 → 主题层 `.Site.Pages` + `findRE` 或 Quartz

**参考实现**：dnaeon 的批量导出脚本（https://gist.github.com/dnaeon/87427d319ae0b0a14bf7bf2bc0c49a77）

### Hugo 主题推荐

| 主题 | Stars | 特点 | SCSS 依赖 |
|---|---|---|---|
| **PaperMod** | 13.8k | 零 JS 依赖、代码复制、搜索、TOC、明暗切换 | 否（对 Guix 非-extended 友好） |
| **Stack** | 5k+ | 卡片式、侧边栏、SCSS+TS | 是（需 Hugo extended） |
| **Blowfish** | — | 最强功能：Mermaid 图表、shortcode 丰富 | 是（需 extended + Node.js） |

## 纯 JS/TS 路线（不经 Markdown、不需 Emacs）

### uniorg（推荐）

| 维度 | 详情 |
|---|---|
| 仓库 | `rasendubi/uniorg` |
| npm | `uniorg-parse`, `uniorg-rehype`, `uniorg-extract-keywords` |
| Stars | 335，27 forks |
| 最后活动 | 2026-06-21 |
| 设计目标 | **"sees org files the same way as org-mode does"** |
| 灵感来源 | 直接从 `org-element.el` 移植 |
| 生态 | unified 生态（与 remark/rehype 同构） |
| License | GPL-3.0 |

**Astro 集成**：
- `astro-org`（npm，v4.0.0，peer dep `astro ^5.0.0`）— 底层用 uniorg-parse + uniorg-rehype + rollup-plugin-orgx
- `@orgajs/astro`（npm，v1.4.0）— 偏 JSX 编译路径

**uniorg 的已知偏差**：见 https://github.com/rasendubi/uniorg/blob/main/docs/deviations-from-org-mode.org

### orgajs / orga-build

| 维度 | 详情 |
|---|---|
| 仓库 | `orgapp/orgajs` |
| npm | `orga`（4.7.1），`orga-build`（0.9.0） |
| Stars | 659 |
| 最后活动 | 2026-06-28（push），2026-03-02（commit） |
| 特点 | JS parser + orga-build（基于 Vite 的 SSG） |
| 取舍 | parser 精度未对标 org-element.el（自有实现） |

## 纯 Emacs 路线（不经 Markdown、需 Emacs 构建）

### org-static-blog

| 维度 | 详情 |
|---|---|
| 仓库 | `bastibe/org-static-blog` |
| Stars | 397 |
| 最后 commit | 2026-04-13 |
| 版本 | 1.7.0 |
| 维护 | 🟢 活跃 |
| 依赖 | 零（仅需 Emacs ≥ 24.3） |
| 功能 | RSS（含 per-tag）、tag 页、归档页、草稿、Open Graph、SEO、多语言 |
| 配置 | 一组 `setq` + `M-x org-static-blog-publish` |

### weblorg

| 维度 | 详情 |
|---|---|
| 仓库 | `emacs-love/weblorg` |
| Stars | 302 |
| 最后 commit | 2025-04-07 |
| 版本 | 0.1.2（停在 2021-09-19） |
| 维护 | 🟡 接近停滞 |
| 依赖 | templatel 0.1.6 + Emacs ≥ 26.1 |
| 特点 | 模板系统最强（templatel = Emacs 版 Jinja），有 simpleblog 完整范例 |

### org-publish + ox-html

| 维度 | 详情 |
|---|---|
| 来源 | Emacs/Org 官方内置（Org manual 第 14 章 Publishing） |
| 维护 | 🟢 随 Emacs 核心，永久 |
| 配置 | `org-publish-project-alist`（property list） |
| 特点 | 最灵活，但不是博客引擎——RSS/tag/归档全要自己写 Elisp |

## Hexo 路线

### hexo-renderer-org（不推荐）

| 维度 | 详情 |
|---|---|
| 仓库 | `coldnew/hexo-renderer-org` |
| Stars | 164 |
| 最后 commit | 2022-03-21（3+ 年不更新） |
| 原理 | 启动 Emacs daemon，用 ox-html 把 .org 转 HTML，喂给 Hexo |
| 问题 | Org AST 在 ox-html 步骤就被压扁，不保留 ID/property 语义 |

## Graph-first / 知识图谱路线

### Quartz + ox-hugo

| 维度 | 详情 |
|---|---|
| 仓库 | `jackyzha0/quartz` |
| 特点 | Quartz 官方支持 ox-hugo 兼容（https://quartz.jzhao.xyz/features/oxhugo-compatibility） |
| 路径 | Org → ox-hugo → Markdown → Quartz 渲染 |
| 适合 | 重视 backlinks/graph 的数字花园 |

### org-roam-ui-lite

| 维度 | 详情 |
|---|---|
| 仓库 | `tani/org-roam-ui-lite` |
| Stars | 23 |
| 最后活动 | 2026-05 |
| 特点 | 从 org-roam files + database 生成静态 digital garden |
| 适合 | 公开 org-roam 笔记库，非传统博客 |

## 已停滞/不推荐

| 工具 | 最后活动 | 原因 |
|---|---|---|
| **Firn** | 2022-08 | 4 年无更新，Alpha 状态 |
| **0WD0 ox-edn** | 2026-08（个人活跃） | 0★/0 fork，个人项目，不可直接采用 |
| **0WD0 Loam** | 2026-08（个人活跃） | 同上，连 GH Pages 部署文档都没写 |
| **lazyblorg** | 2026-04 | 活跃但偏 Karl Voit 个人工作流，`:blog:` tag 约定重 |
