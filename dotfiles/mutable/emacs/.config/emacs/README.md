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
- 交互层重构说明见 [docs/non-modal-prefix-redesign.md](docs/non-modal-prefix-redesign.md)

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

### 前缀分组

| 分组 | 前缀 | 说明 |
| ---- | ---- | ---- |
| 文件 / 缓冲区 / 窗口 / 标签 | `C-x` | 文件、缓冲区、窗口与标签相关操作 |
| 项目 | `C-x p` | 项目切换、项目搜索、项目目录 |
| 搜索 | `M-s` | 当前缓冲区、项目、缓冲区搜索与替换 |
| 跳转 / 错误 | `M-g` | 错误导航、引用查询、返回 / 前进 |
| 代码 / LSP | `C-c l` | 定义、引用、重命名、代码操作、Godot |
| 格式化 | `C-c f` | 缓冲区 / 选区格式化与缩进 |
| 编辑变换 | `C-c e` | 行操作、注释、文本变换、包围、书签 |
| 多光标 / 选区 | `C-x s` | 多光标、整行 / 代码块选区、扩展选区 |
| 折叠 | `C-c z` | 代码折叠 |
| Git | `C-c g` | Git 常用操作 |
| 切换 / 工作区 | `C-c t` | Treemacs、终端、工作区、PDF、主题、小地图 |
| 应用 | `C-c a` | 游戏、日历、邮件 |
| Org 扩展 | `C-c o` | Agenda、Babel、Roam 与 Org 辅助命令 |
| 帮助 | `C-c h` | 快捷键帮助与 Helpful |

### 功能键与其他操作

| 快捷键 | 说明 |
| ------ | ---- |
| `F5` | 切换工作区布局 |
| `F1 ?` | 打开完整快捷键帮助 |
| `C-h/j/k/l` | 左 / 下 / 上 / 右移动 |
| `C-.` | Embark 上下文操作 |
| `C-x C-r` | 最近文件 |
| `M-. / M-,` | 跳转到定义 / 返回 |
| `M-g n / p` | 下一个 / 上一个错误 |

### 鼠标操作

| 操作            | 说明       |
| --------------- | ---------- |
| `右键`          | 上下文菜单 |
| `Ctrl+点击`     | 跳转到定义 |
| `Alt+点击`      | 添加多光标 |
| `侧键前进/后退` | 跳转历史   |

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
