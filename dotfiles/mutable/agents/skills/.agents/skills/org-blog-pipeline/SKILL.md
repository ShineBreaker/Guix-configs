---
name: org-blog-pipeline
description: "Org-mode 博客建站方案选型。触发：用 org 写博客 / org 建站 / org 发布到 web。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [org-mode, blog, static-site, astro, hugo, emacs, publishing]
    related_skills: [architecture-advisor, task-planner]
---

# org-blog-pipeline — Org-mode 博客/站点发布方案选型与实现

用户想在 Emacs 内用 Org-mode 写博客/站点并发布到 web。核心难点不是"能不能导出 HTML"，而是**如何处理 Org 语义的保留/丢失**——ID、CUSTOM_ID、property drawer、org-roam 链接、source block 精确区间等语义在哪一层被压扁，决定了方案的适用范围。

## 第一步：三角约束分析（必做）

先向用户确认三个维度，它们最多同时满足两个：

```
        保留现有 SSG 主题
             / \
            /   \
           /     \
          /  不可行 \
         /         \
保留 Org 语义 ------- 不经过 Markdown
```

| 用户说 | 含义 | 排除的方案 |
|---|---|---|
| "我有现成的 Hexo/Hugo 主题" | 要保留 SSG | 自建管线、纯 Emacs 方案被排除 |
| "不想转 Markdown，会丢元数据" | 不经过 Markdown | ox-hugo、ox-md 被排除 |
| "要保留 ID/property/org-roam 链接" | 保留 Org 语义 | hexo-renderer-org、org-static-blog 被排除 |

**如果不提约束** → 默认推荐 ox-hugo（最成熟）。
**如果要"不经过 Markdown + 保留语义 + 不需要 Emacs 构建"** → uniorg + Astro（见下）。

## 五条架构路线速查

详细工具维护状态、Stars、最后更新时间见 `references/org-publishing-landscape.md`（2026-08 调研数据）。

| 路线 | 不经过 MD | 保留语义 | 不需要 Emacs | 保留现有主题 | 推荐度 |
|---|---|---|---|---|---|
| **ox-hugo + Hugo** | ❌ | ❌ | ✅ | ❌ | ★★★★★（接受 MD 时首选） |
| **uniorg + Astro** | ✅ | ✅ | ✅ | ✅（迁移 EJS→.astro） | ★★★★★（全约束满足时首选） |
| **org-static-blog** | ✅ | 部分 | ❌ | ❌ | ★★★★（纯 Emacs 最简方案） |
| **Hexo + 自建 renderer** | ✅（JSON） | ✅ | ❌ | ✅ | ★★★（工程量可控但有维护成本） |
| **hexo-renderer-org** | ⚠️（经 HTML） | ❌ | ❌ | ✅ | ★★（2022 停更，仅自动转 HTML） |

### 路线 A：ox-hugo + Hugo（最成熟）

- **适用**：用户接受"转换但精致地转换"，front matter 自动生成 + 保存自动导出
- **核心**：one-post-per-subtree（一个 org 文件管理所有文章）+ `.dir-locals.el` 启用 `org-hugo-auto-export-mode` + `hugo server --navigateToChanged` 实时预览
- **org-roam 共存**：需 `(require 'org-id)` + advice 注入 CREATED 日期 + strip-directory 修链接路径。详见 ox-hugo 官方 issue #668/#772 和 dnaeon 的批量导出脚本
- **部署**：GitHub Actions 官方 workflow（`configure-pages` + `upload-pages-artifact` + `deploy-pages`）
- **主题**：PaperMod（13.8k★，首选）、Stack、Blowfish

### 路线 B：uniorg + Astro（推荐 — 唯一全约束满足方案）

- **适用**：用户要不经过 Markdown + 保留 Org 语义 + 不需要 Emacs 构建 + 保留现有主题
- **核心发现**：**uniorg**（npm `uniorg-parse`，335★，活跃维护 2026-06）是一个纯 JS/TS Org parser，**刻意从 `org-element.el` 移植**，追求"sees org files the same way as org-mode does"
- **Astro Content Layer API**（Astro 5.0+）原生支持自定义 `Loader`，可以写一个 `org-loader` 用 uniorg 解析 `.org` 文件直接塞进 content store
- **已有集成**：`astro-org`（npm，v4.0.0，peer dep `astro ^5.0.0`，底层用 uniorg）和 `@orgajs/astro`（v1.4.0，偏 JSX 编译）
- **parser 精度已验证**：见下方"验证方法"
- **主题迁移**：EJS 模板 → `.astro` 组件；浏览器端 TS/CSS 零改动

### 路线 C：org-static-blog（纯 Emacs 最简）

- **适用**：不想引入外部 SSG，零依赖（只需 Emacs ≥ 24.3）
- **维护**：🟢 活跃（v1.7.0，最后 commit 2026-04-13），397★
- **功能**：RSS / tag 页 / 归档页 / 草稿 / Open Graph / SEO 全部开箱即用，一组 `setq` 配置
- **代价**：无主题系统（靠 HTML 注入 + CSS），默认样式朴素

### 路线 D：Hexo + 自建 renderer（保留主题）

- **适用**：用户有定制 Hexo 主题（如自定义 EJS + TS + Vite），不想换 SSG 但要保留 Org 语义
- **做法**：Emacs 导出脚本（org-element → JSON）→ 自定义 Hexo renderer 消费 JSON → EJS 模板渲染
- **代价**：CI 需要 Emacs；需维护导出脚本（~200-400 行 Elisp）和 renderer（~50-100 行 JS）

### 路线 E：hexo-renderer-org（不推荐）

- 164★，最后 commit **2022-03-21**，3+ 年不更新
- 底层是 `ox-html` 一次性转 HTML，**Org AST 在这一步就被压扁**，不满足"保留语义"
- 只是"手动转 Markdown"变成"自动转 HTML"，本质仍是转换路线

## uniorg parser 精度验证方法（路线 B 必做）

**为什么验证**：uniorg 虽然对标 org-element.el，但它是独立实现。在投入迁移前必须验证它对你常用 Org 语法的覆盖度。

**怎么验证**：写一个 unified 管线（`uniorg-parse → uniorg-rehype → rehype-highlight → rehype-stringify`），把代表性 Org 文件跑过去，检查 HTML 输出和 AST 语义。验证脚本模板见 `scripts/verify-uniorg-parser.mjs`。

**关键发现（2026-08 实测）**：

1. **emphasis 边界检测与 Emacs 完全一致**：`**加粗**、`（中文顿号紧贴标记）在 uniorg 和 Emacs ox-html 中**都不解析**，因为顿号不在 Org 的 `post` 字符集里。用空格分隔（`**加粗** 且`）时两者都正确输出 `<strong>`/`<b>`。这不是 parser bug，是 Org 语法本身的规范
2. **Property Drawer 完整保留**：CUSTOM_ID、ID 等 node-property 在 AST 中保留（可用于后续 ID 链接解析）
3. **复选框 `- [X]`/`- [ ]`**：AST 保留了 `checkbox` 属性，但 `uniorg-rehype` 没有渲染成 `data-checked`，需在自定义 loader 中处理
4. **CUSTOM_ID → HTML id**：`uniorg-rehype` 用 headline slug 而非 CUSTOM_ID 做 `id`，需自定义 rehype 插件
5. **25 种 Org 语法结构全部正确解析**：代码高亮、表格、脚注、引用块、LaTeX、COMMENT 块排除、链接类型（https/file/custom-id）、keywords

**与 Emacs 交叉验证 emphasis 边界**（确认 parser 行为一致性）：

```elisp
;; 可复现的交叉验证脚本
(require 'org) (require 'ox-html)
(let ((tests '(("顿号紧贴" . "包含 **加粗**、/斜体/、=代码= 的句子。")
               ("空格分隔" . "包含 **加粗** 且 /斜体/ 和 =代码= 的句子。"))))
  (dolist (test tests)
    (with-temp-buffer
      (insert (concat "#+OPTIONS: toc:nil num:nil\n" (cdr test) "\n"))
      (org-mode)
      (message "[%s] %s" (car test) (org-export-as 'html nil nil t)))))
```

运行 `emacs --batch --script <file>`，输出会显示两种情况下 Emacs ox-html 的解析结果与 uniorg 完全一致。

## 通用注意事项

### Hexo 用户的特殊路径

用户可能已经有定制 Hexo 主题。如果用户说"我有 Hexo 博客"：
1. 先读 `_config.yml`、`package.json`、`themes/<name>/_config.yml` 摸清现有架构
2. 检查是否用了 org-roam（`grep -r "org-roam\|ROAM\|ID:" source/_posts/`）
3. 如果主题投入大（自写模板 + TS + 测试）→ 路线 D（自建 renderer）或路线 B（迁移到 Astro，浏览器端 TS/CSS 可零改动）

### 从 Quartz 迁移

用户用过 Quartz 的情况下：
- Quartz 原生支持 ox-hugo 兼容（官方有专门页面）
- ox-hugo 导出的 Markdown 能直接喂给 Quartz
- 但如果要不经过 Markdown，需要走 uniorg + Astro 或纯 Emacs 方案

### CI 注意事项

- **需要 Emacs 的方案**（org-static-blog、hexo-renderer-org、自建 renderer）：CI 中安装 `emacs-nox`，GitHub Actions 用 `purcell/setup-emacs` action
- **纯 JS 方案**（uniorg + Astro、ox-hugo + Hugo）：CI 不需要 Emacs（ox-hugo 在本地导出 Markdown 后提交即可）
- **Guix 用户**：`guix install hugo` 可能不是 extended 版（不含 SCSS），需要主题支持时用官方二进制

## 0WD0 的自建管线（参考价值）

文章《从 Org 到 Web：建站记》描述了 ox-edn + Loam + SvelteKit 三层管线。架构理念先进（Emacs org-element → EDN → ClojureScript → 静态站点），但 ox-edn（0★）和 Loam（0★）都是作者个人项目，不可直接采用。其设计理念（"不要在 JS/Rust/Clojure 里再实现一个足够像 Org 的 parser"）被 uniorg（刻意从 org-element.el 移植）所满足。
