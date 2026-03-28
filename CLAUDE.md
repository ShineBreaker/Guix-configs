<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# AGENT.md

本文件为在本仓库中工作的 AI 助手提供统一指引。目标是先理解模块边界，再做最小且可验证的修改。

## 概述

这是一个以 Guix 为核心的个人系统配置仓库，内容分成两层：

- `source/`：Guix System / Guix Home 的 Scheme 源配置和 org 文档。
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合, 文件结构应符合 Stow 规范。
- `tmp/`：`maak` 生成的完整配置（临时目录，不应手动编辑）。

仓库不是直接维护一份扁平化的最终配置，而是利用 `maak` 处理 `source/configs` 中的 org 文件，将所有的代码块提取出来并放置在一个文件中后，再继续利用 `maak` 执行所有操作。

`maak` 是这个仓库的核心工具，它的主页上将其描述为

> The infinitely extensible command runner, control plane and project automator à la Make (Guile Scheme - Lisp)

作为一个代码运行器，我们可以封装很多很长的代码，以及相关业务逻辑到 `maak.scm` 中，便于用户以及机器进行直接调用

## 工作优先级

处理本仓库时，按下面顺序理解上下文：

1. 先看当前目录是否存在更近的 `AGENT.md`。
2. 若修改 `dotfiles/emacs/.config/emacs/`，遵循 [dotfiles/emacs/.config/emacs/AGENT.md](./dotfiles/emacs/.config/emacs/AGENT.md)；它比本文件更具体。
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准。

## 仓库结构

当前仓库的关键入口如下：

```text
.
├── CLAUDE.md               # 仓库级 AI 工作指引 (本文档)
├── README.md               # 项目说明文档
├── LICENSE
├── maak.scm                # maak 配置文件
├── source/                 # 配置源码目录
│   ├── channel.scm         # Guix 频道定义
│   ├── channel.lock        # Guix 频道锁文件
│   ├── information.scm     # 全局变量定义
│   ├── configs/            # org mode 格式配置文档
│   │   ├── home-config.org
│   │   └── system-config.org
│   ├── files/              # 静态配置模板与资源文件
│   └── nix/                # Nix 配置 (实验性)
├── dotfiles/               # 用户配置文件树 (Stow 格式)
│   ├── emacs/              # Emacs 配置子树 (含独立 AGENT.md)
│   ├── fcitx5/             # 含 rime 子模块
│   └── ...
├── screenshots/            # 预览截图
└── tmp/                    # 生成的完整配置（临时，运行时创建）
```

额外事实：

- `dotfiles/fcitx5/.local/share/fcitx5/rime` 是 git submodule。
- `maak.scm` 是一个名为 `maak` 的软件的配置文件，`maak` 是一个命令运行器 (command runner)。

## 配置装配模型

### 1. 主入口

- [maak.scm](./maak.scm)：仓库任务入口。
- [source/information.scm](./source/information.scm)：全局变量定义。
- [source/channel.scm](./source/channel.scm)：Guix 频道定义。
- [source/configs/system-config.org](./source/configs/system-config.org)：系统配置说明文档。
- [source/configs/home-config.org](./source/configs/home-config.org)：Home 配置说明文档。

### 2. 聚合方式

- `maak` 会处理 `source/configs` 中的 org 文件，将所有的代码块提取出来并放置在一个文件中。
- 生成后的完整文件会放到 `tmp/`。
- 之后通过调用 `maak` 执行。

### 3. 基础数据源

- [source/information.scm](./source/information.scm)：用户名、channel lock、machine-id、Btrfs 子卷和持久化目录等全局事实来源。
- [source/channel.scm](./source/channel.scm)：Guix 频道定义和锁定。
- 修改用户名、持久化目录、Btrfs 子卷、channel 相关行为时，应优先检查这里是否已经被其他模块引用。

## 目录职责

### 系统配置 (`source/configs/system-config.org`)

定义 `operating-system` 的组成部分，包括：

- 引导器、文件系统、内核、用户、系统包。
- 系统服务定义。
- skeleton 文件配置。

如果是系统层变更，优先修改 `source/configs/system-config.org` 中的对应代码块，生成的 `tmp/system-config.scm` 不应手动编辑。

### Home 配置 (`source/configs/home-config.org`)

定义 `home-environment` 的组成部分，包括：

- 用户级包集合。
- Home 服务定义。
- dotfiles 服务配置，将 `dotfiles/` 中的配置链接到用户家目录。

若某个应用已经由 `dotfiles/` 提供真实配置，优先改对应 dotfile；若需要让 Guix Home 安装、链接或生成它，再修改 `source/configs/home-config.org` 中的相关代码块。

### `source/files/`

放静态模板、原始配置和需要 `computed-substitution-with-inputs` 的文件。适合：

- 需要把包的绝对路径注入模板。
- 不适合直接放进 `dotfiles/` 的生成式配置。

注意：`source/files/` 是源码，会被复制到生成的配置中使用。

### `dotfiles/`

这里是用户空间配置树，最终由 Home 的 dotfiles 服务分发。**添加应用配置文件时，优先放在此处**。

新增应用配置时的完整流程：

1. **在 `dotfiles/` 下创建配置目录**：遵循 Stow 规范，目录结构应模拟目标家目录的相对路径
   - 配置文件通常放在 `dotfiles/<app>/.config/<app>/`
   - 数据文件通常放在 `dotfiles/<app>/.local/share/<app>/`
   - 示例：`dotfiles/foot/.config/foot/foot.ini` → `~/.config/foot/foot.ini`

2. **在 Home 配置中声明**：在 `source/configs/home-config.org` 中添加对应服务的配置
   - 在 `dotfiles-service-type` 的 `packages` 中加入对应的 <app>

修改时注意：

- 保持相对路径与目标家目录一致。
- 不要随意移动目录，否则 Home 链接路径会变化。
- `dotfiles/emacs/.config/emacs/` 是一个独立复杂子系统，有自己的 `AGENT.md`。

## 常用任务

优先使用仓库自带任务入口，而不是手写长命令：

```bash
maak init
maak system
maak home
maak rebuild
```

`maak` 中的重要行为：

- `init`：安装系统到 `/mnt`。
- `system`：`guix system reconfigure`。
- `home`：`guix home reconfigure`。
- `rebuild`：先 system 再 home，并更新 locate 数据库。

如果只是检查结构，通常不需要真的执行这些命令。

## 修改约定

### Do

- **优先 Home 而非 System**：用户级配置、用户软件包、用户服务优先放在 Home 配置中；System 配置仅保留系统级必需内容（引导、内核、文件系统、系统级服务等）。
- 优先在最具体的模块中修改，而不是改聚合入口。
- 保持现有 `(load ...)` 风格和变量命名习惯，例如 `%services-config`、`%packages-list`。
- **新增应用配置时遵循完整流程**：
  1. 将配置文件放入 `dotfiles/<app>/`（遵循 Stow 规范，路径模拟目标家目录结构）
  2. 在 `source/configs/home-config.org` 中将该应用包加入用户包列表
  3. 在 `home-dotfiles-configuration` 的 `packages` 中添加app的名称，即你创建的相关目录的名称
- 新增程序配置时，同时考虑三处是否需要联动：
  - 包是否要加入 `source/` 中的系统或用户包定义
  - 服务是否要加入 `source/` 中的系统或 Home 服务定义
  - 配置文件是否要放到 `dotfiles/` 或 `configs/files/`
- 当 README 的结构描述过时，如有必要可顺手修正文档，但不要把错误结构继续复制进新文件。

### Don't

- 不要把生成出来的 `tmp/*.scm` 当成源码维护。
- 不要直接编辑子模块内容来规避仓库层问题，除非任务明确要求修改该子模块。
- 不要在根级 `AGENT.md` 里重复 Emacs 子树的细节说明；那部分应留给其局部 `AGENT.md`。
- 不要假设 README 中的文件名一定存在，先核对实际路径。
- **不要把本应放在 Home 层的配置硬塞到 System 层**：遵循"能 Home 不 System"原则，用户级工具和配置优先放在 Home 配置中，System 配置只保留系统级必需内容（如引导、内核、文件系统、系统服务等）。

## 验证建议

能做局部验证时，优先局部验证：

- Scheme 结构检查：至少重新阅读被修改模块与其聚合入口，确认变量名、`load` 路径和括号层级一致。
- 任务流验证：涉及装配逻辑时，优先考虑是否需要执行 `maak home` 或 `... system`。
- dotfiles 验证：确认路径是否仍然与目标家目录一致。

如果当前环境缺少 `guix`、`maak` 或相关依赖，明确说明未执行实际重配置即可，不要伪称已验证。

## 面向 AI 的决策规则

- 用户提到"系统配置"时，通常先看 `source/` 中的系统相关文件。
- 用户提到"用户/软件配置"时，通常先看 `source/` 中的 Home 配置和 `dotfiles/`；**优先使用 Home 配置，避免不必要的 System 层修改**。
- 用户提到"为什么最终配置里出现某个字段"时，沿着 `source/` 中的 `load` 链回溯，然后检查生成的 `tmp/*.scm`。
- 用户提到 Emacs 时，先切换到 [dotfiles/emacs/.config/emacs/AGENT.md](./dotfiles/emacs/.config/emacs/AGENT.md) 的规则集。

## 已知风险点

- `dotfiles/fcitx5/.local/share/fcitx5/rime` 是子模块，操作前先确认任务是否真的要求改动它。
- 不要手动编辑 `tmp/` 目录中的文件，它们是由 `maak.scm` 自动生成的。
- 优先修改 `source/` 中的源文件，而不是生成后的 `tmp/*.scm`。
