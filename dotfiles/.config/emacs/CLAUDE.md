<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# CLAUDE.md

本文件为 Claude Code (claude.ai/code) 提供在此仓库中工作的指导。

## 概述

这是一个基于 Guix 的模块化 Emacs 配置，提供类似 JetBrains IDE 的开发体验。所有包由 Guix 管理（不使用 package.el），配置采用 Leader 键系统（Spacemacs/Doom 风格）减少对 Ctrl 键的依赖。

## 架构设计

### 加载顺序

1. **early-init.el** - GUI 初始化前执行（GC 优化、防闪屏设置）
2. **init.el** - 主入口，加载核心模块和配置模块
3. **core/** - 核心基础设施（bootstrap、lib、autoloads）
4. **configs/** - 按类别组织的功能模块

### 目录结构

```
.emacs.d/
├── early-init.el       # 启动优化，GUI 前执行
├── init.el             # 主入口，加载所有模块
├── core/
│   ├── bootstrap.el    # 路径常量、Guix 环境检测
│   ├── lib.el          # 工具函数（my/load-config 等）
│   └── autoloads.el    # 自动加载定义
├── configs/
│   ├── system/         # Guix 集成、启动设置
│   ├── ui/             # 外观、仪表板、工作区布局
│   ├── editor/         # 快捷键、补全、编辑功能
│   ├── coding/         # LSP、语言特定配置
│   ├── tools/          # Git、项目、终端、AI、邮件、日历
│   └── Documents/Org//            # Org Mode 和 Org-roam
├── docs/               # 用户文档
└── var/                # 运行时数据（自动生成）
```

### 配置加载模式

配置通过 core/lib.el 中定义的 `my/load-config` 函数加载：

```elisp
(my/load-config "类别" "文件名.el")
```

展开为 `configs/类别/文件名.el` 并在文件存在时加载。

## 包管理

**重要**：此配置使用 Guix 管理所有包。

- `package.el` 已禁用（`package-enable-at-startup nil`）
- `use-package-always-ensure` 设为 `nil`
- 所有包必须通过 Guix 安装，不能通过 Emacs 包管理器
- 添加新包时使用 `use-package` 声明，但不要设置 `:ensure t`

### 安装依赖

```bash
# 通过 Guix 安装 Emacs 包
guix install emacs-<包名>

# 安装 LSP 服务器
guix install python-lsp-server  # Python
guix install ccls                # C/C++
guix install rust-analyzer       # Rust

# 安装外部工具
guix install notmuch             # 邮件索引
guix install ripgrep             # 快速搜索
```

## 测试配置更改

```bash
# 带调试输出测试
emacs --debug-init

# 检查启动时间
# 然后在 Emacs 中：M-x emacs-init-time

# 不重启重新加载配置
# 在 Emacs 中：在 init.el 中执行 M-x eval-buffer
```

## 核心子系统

### 工作区布局（configs/ui/workspace.el）

- 按 `SPC t l` 或 `F5` 触发 VS Code 风格布局
- 左侧：Treemacs 文件树
- 中间：编辑器
- 底部：vterm 终端
- 右侧：AI 面板

### AI 集成（configs/tools/ai.el）

- 使用 Ellama + DashScope API
- API 密钥存储在 GNOME Keyring 或 `OPENAI_API_KEY` 环境变量
- 配置方法：`secret-tool store --label="DashScope API Key" service emacs-ai provider dashscope`
- 快捷键：`SPC a c`（对话）、`SPC a q`（询问）、`SPC a e`（编辑代码）

### LSP 配置（configs/coding/lsp.el）

- LSP 服务器必须先通过 Guix 安装
- 使用 `my/executable-find-required` 检查可执行文件
- 找不到 LSP 服务器时会警告而不是静默失败

### Git 管理（configs/tools/git.el）

- 使用 Magit 和 magit-todos
- `SPC g s` 或 `C-x g` 打开 Magit 状态页面
- 核心操作：`s`（暂存）、`c c`（提交）、`P p`（推送）、`F p`（拉取）

### 项目管理（configs/tools/project.el）

- 使用 Projectile
- 自动识别包含 `.git`、`.projectile` 等标记的目录
- Leader 键前缀：`SPC p`（推荐）或传统前缀：`C-c p`

### Org Mode（configs/Documents/Org/Documents/Org/-mode.el）

- 文件位置：`~/Documents/Org/`
- Org-roam 笔记：`~/Documents/Org/roam/`
- 集成日历（Calfw）和待办事项管理

## 常用快捷键

### Leader 键系统（推荐）

配置采用 Spacemacs/Doom Emacs 风格的 Leader 键设计，减少对 Ctrl 键的依赖。

**Leader 键**：`SPC`（空格键，在 Evil Normal/Visual 模式下）
**Local Leader 键**：`,`（逗号，针对特定 major mode）

主要快捷键（在 Evil Normal/Visual 模式下）：

| 类别     | 快捷键      | 说明                |
| -------- | ----------- | ------------------- |
| **文件** | `SPC f f`   | 打开文件            |
|          | `SPC f s`   | 保存文件            |
|          | `SPC f r`   | 最近文件            |
| **缓冲区** | `SPC b b` | 切换缓冲区          |
|          | `SPC b d`   | 关闭缓冲区          |
|          | `SPC b n/p` | 下一个/上一个缓冲区 |
| **窗口** | `SPC w s/v` | 水平/垂直分割       |
|          | `SPC w d`   | 关闭窗口            |
|          | `SPC w h/j/k/l` | 切换到左/下/上/右窗口 |
| **项目** | `SPC p f`   | 项目查找文件        |
|          | `SPC p s`   | 项目搜索            |
|          | `SPC p p`   | 切换项目            |
| **搜索** | `SPC s s`   | 搜索当前文件        |
|          | `SPC s p`   | 搜索项目            |
| **Git**  | `SPC g s`   | Git 状态            |
|          | `SPC g b`   | Git blame           |
| **AI**   | `SPC a a`   | 打开 AI 面板        |
|          | `SPC a c`   | AI 对话             |
|          | `SPC a q`   | 询问代码            |
|          | `SPC a e`   | 编辑代码            |
| **切换** | `SPC t t`   | 文件树              |
|          | `SPC t v`   | 终端                |
|          | `SPC t l`   | 工作区布局          |
| **Org**  | `SPC o a`   | Org 议程            |
|          | `SPC o n f` | 查找笔记            |
| **帮助** | `SPC h f/v/k` | 查看函数/变量/按键 |
|          | `SPC h ?`   | 快捷键帮助          |
| **快速** | `SPC SPC`   | M-x 命令            |

### 传统快捷键（备选）

保留部分 Ctrl 快捷键，在 Emacs 状态下或作为备选使用：

| 功能         | 快捷键    | 说明                |
| ------------ | --------- | ------------------- |
| 项目查找文件 | `C-p`     | 快速查找            |
| 全文搜索     | `C-S-f`   | Ripgrep 搜索        |
| 切换缓冲区   | `C-S-b`   | 快速切换            |
| 文件树       | `C-c t`   | Treemacs            |
| 工作区布局   | `F5`      | VS Code 风格        |
| AI 对话      | `C-c a c` | Ellama 对话         |
| Evil 模式    | `C-c v v` | 切换到 Vim 普通模式 |

## 修改配置

### 添加新的配置模块

1. 在相应的 configs/ 子目录中创建文件
2. 使用 `use-package` 声明（不要设置 `:ensure t`）
3. 在 init.el 中添加 `(my/load-config "类别" "文件名.el")`
4. 确保记录所有外部依赖

### 添加新包

1. 通过 Guix 安装：直接创建一个 `emacs.scm` ，里面写下需要安装的软件包，以便用户直接复制粘贴到自己的Guix配置文件中
2. 在相应配置文件中添加 `use-package` 声明
3. 确保 `use-package-always-ensure nil`（或省略 :ensure）
4. 使用 `emacs --debug-init` 测试

### 修改快捷键

- Leader 键绑定：编辑 configs/editor/leader.el
- 传统快捷键：编辑 configs/editor/keybindings.el
- Leader 键系统使用 general.el 管理，提供 which-key 提示

### 添加新语言支持

1. 安装 LSP 服务器：参考 **添加新包** 的办法
2. 在 configs/coding/languages.el 中添加语言配置
3. 使用 `my/executable-find-required` 检查 LSP 服务器是否存在

## Guix 环境检测

配置通过以下方式检测 Guix 环境：

- `GUIX_ENVIRONMENT` 环境变量
- `~/.guix-profile` 目录是否存在
- 检测结果存储在 `my/in-guix-environment-p` 常量中

## 常见问题排查

### Notmuch 无法启动

确保已安装并配置 notmuch：

```bash
guix install notmuch
notmuch setup
notmuch new
```

### Org-roam 数据库错误

初始化数据库：

```elisp
M-x org-roam-db-sync
```

### AI 工具无法使用

检查 API Key 配置：

```elisp
M-: (my/ai-read-api-key)
```

或设置环境变量：

```bash
export OPENAI_API_KEY="your-api-key"
```

### LSP 无法启动

确保已通过 Guix 安装对应的 LSP 服务器：

- 向用户索要一份 `emacs.scm` ，或者查看现有的 `emacs.scm` ，确保相应的软件包已经安装到了电脑中。

检查是否在 PATH 中：

```bash
which python-lsp-server
```

### 启动时出错

使用调试模式查看详细错误：

```bash
emacs --debug-init
```

## 重要注意事项

### 包管理原则

- **绝对不要**在配置中使用 `:ensure t`
- **绝对不要**尝试通过 `package-install` 安装包
- 所有包必须通过 guix 安装 (写对应配置文件 -> 请求用户安装)
- 配置中只使用 `use-package` 进行声明和配置

### 配置文件编码

- 所有配置文件使用 UTF-8 编码
- 注释和文档主要使用中文
- 修改文件时保持与现有注释语言的一致性

### 启动优化

- early-init.el 中的 GC 设置在启动后会被重置
- 不要在 early-init.el 中加载包或执行耗时操作
- 防闪屏设置（深色背景）在主题加载前生效

## 文档参考

- **docs/README.md** - 快速开始指南（中文）
- **docs/GUIDE.md** - 详细功能文档（中文）
- **docs/changelog.md** - 变更历史

## 核心工具函数

定义在 core/lib.el 中：

- `my/load-config` - 加载配置模块
- `my/executable-find-required` - 检查可执行文件并给出友好提示

## 路径常量

定义在 core/bootstrap.el 中：

- `my/emacs-dir` - Emacs 配置根目录
- `my/core-dir` - 核心模块目录
- `my/configs-dir` - 配置模块目录
- `my/guix-profile` - Guix profile 路径
- `my/in-guix-environment-p` - 是否在 Guix 环境中
