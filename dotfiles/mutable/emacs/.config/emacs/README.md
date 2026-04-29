<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Guix Emacs 配置

基于 Guix 包管理的模块化 Emacs 配置，默认按 daemon/client 工作流使用，目标是提供稳定、可复现、接近现代 IDE 的编辑体验。

## 特点

- 所有第三方包都由 Guix 安装，不使用 `package.el`
- 默认工作流是 `emacs --fg-daemon` + `emacsclient`
- 以非模态编辑 + Emacs 原生前缀分组为核心交互
- 使用 Vertico/Consult/Embark/Corfu 体系完成补全、搜索和操作
- 使用 Eglot、Apheleia、Flycheck、Treemacs、Projectile、Magit 等构建 IDE 能力
- 所有模块都拆分在 `configs/` 下，具体行为优先看对应文件的 `;;; Commentary:`
- 交互层采用多前缀分组设计：按命令类别分散到 `C-x`、`M-s`、`M-g`、`C-c` 等 Emacs 原生前缀，高频操作贴近 Windows / IDE 习惯（`C-s` 保存、`C-f` 搜索、`C-p` 找文件），详见下方 [常用快捷键](#常用快捷键)
- `C-h` / `C-j` / `C-k` / `C-l` 被绑定为方向键（左 / 下 / 上 / 右），帮助前缀改用 `C-c h` 和 `F1 ?`

## 目录结构

```text
~/.config/emacs/
├── early-init.el
├── init.el
├── core/
│   ├── bootstrap.el
│   └── lib.el
├── diagnose/
│   ├── diagnostic.el
│   ├── diagnostic-*.el
│   ├── run-tests.el
│   └── test-*.el
├── configs/
│   ├── system/
│   │   ├── startup.el
│   │   └── guix.el
│   ├── ui/
│   │   ├── appearance.el
│   │   ├── color-scheme.el
│   │   ├── dashboard.el
│   │   └── workspace.el
│   ├── editor/
│   │   ├── keybindings.el
│   │   ├── prefix-keymaps.el
│   │   ├── mouse.el
│   │   ├── help.el
│   │   ├── completion.el
│   │   ├── folding.el
│   │   ├── navigation.el
│   │   └── editing.el
│   ├── coding/
│   │   ├── lsp.el
│   │   ├── format.el
│   │   ├── flycheck.el
│   │   └── languages.el
│   ├── tools/
│   │   ├── git.el
│   │   ├── project.el
│   │   ├── terminal.el
│   │   ├── pdf.el
│   │   ├── mail.el
│   │   ├── calendar.el
│   │   └── games.el
│   └── org/
│       ├── org-mode.el
│       ├── org-babel.el
│       ├── org-export.el
│       └── org-todo.el
├── AGENTS.md
└── README.md
```

## 当前已接入的组件

### 系统与基础

- `gcmh`：GC 优化
- `auto-compile`：保存时自动编译配置
- `no-littering`：统一管理缓存和 `custom.el`
- `savehist` / `recentf` / `desktop`：历史记录和会话恢复

### UI

- `dashboard`：启动面板
- `ef-themes`：主题系统
- `doom-modeline`：模式行
- 内建 `tab-line`：文件标签页
- `treemacs` + `treemacs-nerd-icons`：文件树
- `dirvish`：目录浏览
- `minimap`：代码小地图
- `nerd-icons`：图标体系

### 编辑器核心

- `which-key`
- `helpful`
- `ws-butler`
- `diff-hl`
- `expand-region`
- `multiple-cursors`
- `origami` + `origami-ts`
- `symbol-overlay`
- `rainbow-delimiters`
- `eldoc-box`

### 补全与搜索

- `vertico`
- `marginalia`
- `orderless`
- `consult`
- `embark` + `embark-consult`
- `corfu` + `corfu-terminal`
- `cape`
- `kind-icon`

### 编程能力

- `eglot`
- `apheleia`
- `flycheck`
- `posframe`
- Tree-sitter 语法库：`bash`、`c`、`cpp`、`css`、`dockerfile`、`gdscript`、`go`、`html`、`java`、`javascript`、`json`、`kdl`、`nix`、`python`、`rust`、`typescript`

### 语言支持

- `csharp-mode`（Emacs 30 内置）
- `arei`
- `fish-mode` + `fish-completion`
- `helm-fish-completion`
- `gdscript-mode`
- `json-mode`
- `kdl-mode`
- `kotlin-mode`
- `markdown-mode`
- `nix-mode`
- `rust-mode`
- `sly`
- `typescript-mode`
- `web-mode`
- `yaml` + `yaml-mode`
- `yasnippet` + `yasnippet-snippets`
- `zig-mode`

语言相关的 mode、LSP、formatter 和折叠注册表统一维护在 `configs/coding/languages.el`。

### 工具

- `magit` + `magit-todos`
- `git-messenger`
- `git-timemachine`
- `projectile`
- `vterm`
- `pdf-tools`
- `notmuch`
- `calfw`
- `2048-game`

### Org 生态

- `org`
- `org-modern`
- `org-appear`
- `org-roam`
- `ox-gfm`
- `htmlize`

## 安装依赖

如果你直接复用上游 `Guix-configs` 的 Home 配置，以 `source/configs/home-config.org` 中的 `emacs-services` 为准。下面这份清单与当前仓库配置一致：

```scheme
(list (service home-emacs-service-type
               (home-emacs-configuration
                (emacs emacs-pgtk)
                (shepherd-requirement '(graphical-session))
                (packages (specifications->manifest
                           '(;; Emacs 核心与基础
                             "emacs-auto-compile"
                             "emacs-gcmh"
                             "emacs-no-littering"
                             "emacs-pgtk:doc"
                             "emacs-use-package"

                             ;; 补全与迷你缓冲区
                             "emacs-cape"
                             "emacs-consult"
                             "emacs-corfu"
                             "emacs-corfu-terminal"
                             "emacs-embark"
                             "emacs-marginalia"
                             "emacs-orderless"
                             "emacs-vertico"

                             ;; 界面与外观
                             "emacs-dashboard"
                             "emacs-doom-modeline"
                             "emacs-ef-themes"
                             "emacs-kind-icon"
                             "emacs-minimap"
                             "emacs-nerd-icons"
                             "emacs-rainbow-delimiters"
                             "emacs-treemacs"
                             "emacs-treemacs-nerd-icons"
                             "emacs-which-key"

                             ;; 编辑与导航
                             "emacs-diff-hl"
                             "emacs-dirvish"
                             "emacs-expand-region"
                             "emacs-helpful"
                             "emacs-multiple-cursors"
                             "emacs-origami"
                             "emacs-origami-ts"
                             "emacs-symbol-overlay"
                             "emacs-ws-butler"
                             "emacs-eldoc-box"

                             ;; 开发工具
                             "emacs-apheleia"
                             "emacs-flycheck"
                             "emacs-posframe"
                             "emacs-vterm"

                             ;; 编程语言支持
                             "emacs-arei"
                             "emacs-fish-mode"
                             "emacs-fish-completion"
                             "emacs-helm-fish-completion"
                             "emacs-gdscript-mode"
                             "emacs-json-mode"
                             "emacs-kdl-mode"
                             "emacs-kotlin-mode"
                             "emacs-markdown-mode"
                             "emacs-nix-mode"
                             "emacs-rust-mode"
                             "emacs-sly"
                             "emacs-typescript-mode"
                             "emacs-web-mode"
                             "emacs-yaml"
                             "emacs-yaml-mode"
                             "emacs-yasnippet"
                             "emacs-yasnippet-snippets"
                             "emacs-zig-mode"

                             ;; 版本控制与项目管理
                             "emacs-git-messenger"
                             "emacs-git-timemachine"
                             "emacs-magit"
                             "emacs-magit-todos"
                             "emacs-projectile"

                             ;; Org Mode 生态
                             "emacs-htmlize"
                             "emacs-org"
                             "emacs-org-appear"
                             "emacs-org-modern"
                             "emacs-org-roam"
                             "emacs-ox-gfm"

                             ;; 额外工具
                             "emacs-2048-game"
                             "emacs-calfw"
                             "emacs-notmuch"
                             "emacs-pdf-tools"

                             ;; Tree-sitter（保留更宽的语言覆盖）
                             "tree-sitter"
                             "tree-sitter-bash"
                             "tree-sitter-c"
                             "tree-sitter-cpp"
                             "tree-sitter-css"
                             "tree-sitter-dockerfile"
                             "tree-sitter-gdscript"
                             "tree-sitter-go"
                             "tree-sitter-html"
                             "tree-sitter-java"
                             "tree-sitter-java-properties"
                             "tree-sitter-javascript"
                             "tree-sitter-json"
                             "tree-sitter-kdl"
                             "tree-sitter-nix"
                             "tree-sitter-python"
                             "tree-sitter-rust"
                             "tree-sitter-typescript"))))))
```

## 快速开始

### 1. 获取配置

```bash
git clone https://codeberg.org/BrokenShine/.emacs.d ~/.config/emacs
```

### 2. 安装 Guix 包

把上面的包清单加入你的 Guix Home 配置，然后执行对应的 `guix home reconfigure`。

### 3. 启动 Emacs

推荐工作流：

```bash
herd restart emacs-daemon
emacsclient -c
```

也可以直接使用 standalone：

```bash
emacs
```

## 常用快捷键

### 交互设计

本配置按命令类别分散到 Emacs 原生前缀：

- 文件和窗口 → `C-x`（Emacs 原生语义）
- 项目 → `C-x p`（Emacs 29+ 原生项目前缀）
- 搜索 → `M-s`（Emacs 原生搜索前缀）
- 跳转与错误 → `M-g`（Emacs 原生跳转前缀）
- 用户扩展能力 → `C-c` 下的子前缀

记忆方式是"先判断命令属于哪一类，再进对应前缀"，而非"先记一个总入口，再记整棵命令树"。
`C-h` / `C-j` / `C-k` / `C-l` 保留为方向键，帮助前缀改用 `C-c h` 和 `F1 ?`。

### 高频直达键

贴近 Windows / 常见 IDE 习惯的高频操作：

| 快捷键  | 说明           |
| ------- | -------------- |
| `C-s`   | 保存           |
| `C-f`   | 当前缓冲区搜索 |
| `C-S-f` | 项目全文搜索   |
| `C-p`   | 项目内找文件   |
| `C-S-b` | 切换缓冲区     |

### 前缀分组

#### 总览

| 分组                        | 前缀    | 说明                                      |
| --------------------------- | ------- | ----------------------------------------- |
| 文件 / 缓冲区 / 窗口 / 标签 | `C-x`   | 文件、缓冲区、窗口与标签相关操作          |
| 项目                        | `C-x p` | 项目切换、项目搜索、项目目录              |
| 搜索与替换                  | `M-s`   | 当前缓冲区、项目、缓冲区搜索与替换        |
| 跳转 / 错误                 | `M-g`   | 错误导航、引用查询、返回 / 前进           |
| 代码 / LSP                  | `C-c l` | 定义、引用、重命名、代码操作、Godot       |
| 格式化                      | `C-c f` | 缓冲区 / 选区格式化与缩进                 |
| 编辑变换                    | `C-c e` | 行操作、注释、文本变换、包围、书签        |
| 多光标 / 选区               | `C-x s` | 多光标、整行 / 代码块选区、扩展选区       |
| 折叠                        | `C-c z` | 代码折叠                                  |
| Git                         | `C-c g` | Git 常用操作                              |
| 切换 / 工作区               | `C-c t` | Treemacs、终端、工作区、PDF、主题、小地图 |
| 应用                        | `C-c a` | 游戏、日历、邮件                          |
| Org 扩展                    | `C-c o` | Agenda、Babel、Roam 与 Org 辅助命令       |
| 帮助                        | `C-c h` | 快捷键帮助与 Helpful                      |

#### 文件 / 缓冲区 / 窗口 / 标签 — `C-x`

| 快捷键                  | 说明           |
| ----------------------- | -------------- |
| `C-x C-f`               | 打开文件       |
| `C-x C-s`               | 保存           |
| `C-x C-w`               | 另存为         |
| `C-x C-r`               | 最近文件       |
| `C-x P`                 | 打开 PDF       |
| `C-x b`                 | 切换缓冲区     |
| `C-x B`                 | 缓冲区列表     |
| `C-x k`                 | 关闭当前缓冲区 |
| `C-x 2 / 3 / 0 / 1 / o` | 窗口分割与切换 |
| `C-x t ...`             | 标签相关操作   |

#### 项目 — `C-x p`

| 快捷键        | 说明                    |
| ------------- | ----------------------- |
| `C-x p p`     | 切换项目                |
| `C-x p f`     | 项目内找文件            |
| `C-x p s`     | 项目全文搜索            |
| `C-x p o / O` | 打开项目目录 / 目录浏览 |
| `C-x p k`     | 关闭项目缓冲区          |

#### 搜索与替换 — `M-s`

| 快捷键  | 说明           |
| ------- | -------------- |
| `M-s l` | 搜索当前缓冲区 |
| `M-s p` | 搜索项目       |
| `M-s b` | 搜索缓冲区     |
| `M-s r` | 项目范围替换   |

#### 跳转与错误 — `M-g`

| 快捷键      | 说明                |
| ----------- | ------------------- |
| `M-.`       | 跳转到定义          |
| `M-,`       | 返回                |
| `M-g n / p` | 下一个 / 上一个错误 |
| `M-g l`     | 错误列表            |
| `M-g r`     | 查找引用            |
| `M-g h`     | 显示悬停信息        |
| `M-g b / f` | 后退 / 前进         |

#### 代码 / LSP — `C-c l`

| 快捷键        | 说明           |
| ------------- | -------------- |
| `C-c l d`     | 跳转到定义     |
| `C-c l r`     | 查找引用       |
| `C-c l a`     | 代码操作       |
| `C-c l q`     | 快速修复       |
| `C-c l n`     | 重命名         |
| `C-c l c`     | 触发补全       |
| `C-c l s`     | 显示签名       |
| `C-c l e`     | 错误列表       |
| `C-c l t`     | 切换 Flycheck  |
| `C-c l g ...` | Godot 相关操作 |

#### 格式化 — `C-c f`

| 快捷键        | 说明             |
| ------------- | ---------------- |
| `C-c f f`     | 智能格式化       |
| `C-c f b`     | 格式化整个缓冲区 |
| `C-c f r`     | 格式化选区       |
| `C-c f i / I` | 增加 / 减少缩进  |

#### 编辑变换 — `C-c e`

| 快捷键        | 说明          |
| ------------- | ------------- |
| `C-c e l ...` | 行操作        |
| `C-c e c ...` | 注释操作      |
| `C-c e t ...` | 文本变换      |
| `C-c e s ...` | 包围 / 去包围 |
| `C-c e b ...` | 书签          |

#### 多光标 / 选区 — `C-x s`

| 快捷键            | 说明                       |
| ----------------- | -------------------------- |
| `C-x s n / p / a` | 标记下一个 / 上一个 / 全部 |
| `C-x s s / S`     | 跳过并标记                 |
| `C-x s l / f`     | 选中整行 / 代码块          |
| `C-x s e / E`     | 扩大 / 缩小选区            |

#### 折叠 — `C-c z`

| 快捷键        | 说明                |
| ------------- | ------------------- |
| `C-c z a`     | 切换折叠            |
| `C-c z c / o` | 关闭 / 打开当前折叠 |
| `C-c z m / r` | 全部折叠 / 全部展开 |

#### Git — `C-c g`

| 快捷键                | 说明                         |
| --------------------- | ---------------------------- |
| `C-x g`               | Magit 状态页                 |
| `C-c g s`             | Git 状态                     |
| `C-c g b / l / d / t` | blame / 日志 / 差异 / 时光机 |
| `C-c g S / D`         | stage / 丢弃                 |
| `C-c g F / P`         | pull / push                  |

#### 切换 / 工作区 / 工具面板 — `C-c t`

| 快捷键        | 说明                       |
| ------------- | -------------------------- |
| `C-c t t`     | Treemacs                   |
| `C-c t r`     | 在 Treemacs 中定位当前文件 |
| `C-c t d`     | 目录浏览                   |
| `C-c t v`     | 终端                       |
| `C-c t l`     | 工作区布局                 |
| `C-c t p / P` | PDF 显示切换               |
| `C-c t F`     | 保存时格式化               |
| `C-c t c`     | 颜色方案同步               |
| `C-c t h`     | 文档弹窗                   |
| `C-c t m`     | 代码小地图                 |

#### 应用 — `C-c a`

| 快捷键        | 说明 |
| ------------- | ---- |
| `C-c a g ...` | 游戏 |
| `C-c a c`     | 日历 |
| `C-c a m`     | 邮件 |

#### Org 扩展 — `C-c o`

| 快捷键        | 说明                   |
| ------------- | ---------------------- |
| `C-c o a`     | 议程                   |
| `C-c o b ...` | Babel                  |
| `C-c o i / I` | 插入代码块             |
| `C-c o r ...` | TODO、归档、窄化、标题 |
| `C-c o n ...` | Roam                   |

#### 帮助 — `C-c h`

| 快捷键    | 说明               |
| --------- | ------------------ |
| `C-c h f` | 函数帮助           |
| `C-c h v` | 变量帮助           |
| `C-c h k` | 按键帮助           |
| `C-c h m` | 模式帮助           |
| `C-c h B` | 查看当前上下文绑定 |
| `C-c h ?` | 完整快捷键帮助     |

### 功能键

| 快捷键 | 说明               |
| ------ | ------------------ |
| `F5`   | 切换工作区布局     |
| `F1 ?` | 打开完整快捷键帮助 |
| `C-.`  | Embark 上下文操作  |

### 鼠标操作

鼠标作为一等输入层，与键盘操作享有同等地位：

| 操作          | 说明       |
| ------------- | ---------- |
| `右键`        | 上下文菜单 |
| `C-<mouse-1>` | 跳转到定义 |
| `M-<mouse-1>` | 添加多光标 |
| `S-<mouse-1>` | 扩展选区   |
| `<mouse-8>`   | 后退       |
| `<mouse-9>`   | 前进       |

### which-key 汉化布局

`which-key` 的说明文本已集中汉化，并修复了中英文混排时的列对齐问题：

- 说明文本收口到 `configs/i18n/which-key-descriptions.el`
- 列补齐逻辑改为按显示宽度计算，按可用区域等分列宽
- 默认三列布局，宽屏可升至四列，窄窗口自动降至两列
- 中文描述按显示宽度截断，不再因全角字符错位

## Troubleshooting

### `Cannot open load file`

通常表示对应 Guix 包未安装，或当前 Emacs 没运行在包含这些包的 profile 中。

### LSP 无法启动

这个仓库只配置 Emacs 侧，LSP server 仍需单独安装。例如：

```bash
guix install python-lsp-server
guix install ccls
guix install gopls
guix install omnisharp
guix install rust-analyzer
```

formatter 也依赖外部工具。例如 YAML 走 `yq`，Go 走 `gofmt`（随 `go` 提供）。

### 主题没有跟随系统深浅色切换

本配置使用 `ef-themes`，并通过 `configs/ui/color-scheme.el` 跟随 Darkman 的 D-Bus 状态。先确认：

- `darkman` 正常运行
- `nl.whynothugo.darkman` 的 D-Bus 服务可访问
- `var/color-scheme-state.el` 可写

### Notmuch 无法使用

```bash
guix install notmuch
notmuch setup
notmuch new
```

### Org-roam 数据库异常

在 Emacs 中执行：

```text
M-x org-roam-db-sync
```

### 验证配置

```bash
emacs --batch --eval "(message \"%s\" (emacs-init-time))"
emacs --debug-init
emacs --batch -L . -L core -L diagnose -L configs -l diagnose/run-tests.el
```

## 相关文档

- [AGENTS.md](./AGENTS.md)
- [上游仓库](https://codeberg.org/BrokenShine/Guix-configs)
