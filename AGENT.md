<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# AGENT.md

本文件为在本仓库中工作的 AI 助手提供统一指引。目标是先理解模块边界，再做最小且可验证的修改。

## 概述

这是一个以 Guix 为核心的个人系统配置仓库，内容分成两层：

- `configs/`：Guix System / Guix Home 的 Scheme 源配置。
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合。

仓库不是直接维护一份扁平化的最终配置，而是通过 `maak.scm` 读取 `configs/main/*.scm`，递归展开其中的 `(load ...)`，在 `tmp/` 中生成完整配置后，再交给 `guix time-machine` 执行。

## 工作优先级

处理本仓库时，按下面顺序理解上下文：

1. 先看当前目录是否存在更近的 `AGENT.md`。
2. 若修改 `dotfiles/.config/emacs/`，遵循 [dotfiles/.config/emacs/AGENT.md](./dotfiles/.config/emacs/AGENT.md)；它比本文件更具体。
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准。

## 仓库结构

当前仓库的关键入口如下：

```text
.
├── AGENT.md
├── README.md
├── maak.scm
├── configs/
│   ├── information.scm
│   ├── channel.scm
│   ├── channel.lock
│   ├── main/
│   │   ├── init-config.scm
│   │   ├── system-config.scm
│   │   └── home-config.scm
│   ├── system/
│   │   ├── *.scm
│   │   └── services/*.scm
│   ├── home/
│   │   ├── modules.scm
│   │   ├── package.scm
│   │   ├── services.scm
│   │   └── services/**/*.scm
│   └── files/
│       └── 静态配置模板与资源文件
├── dotfiles/
│   └── 真实用户配置文件树
├── setup/
│   └── 独立子模块
└── screenshots/
```

额外事实：

- `setup/` 是 git submodule。
- `dotfiles/.local/share/fcitx5/rime` 也是 git submodule。
- `README.md` 中提到的 `justfile`、根目录 `config.scm` 等文件目前并不存在。

## 配置装配模型

### 1. 主入口

- [maak.scm](./maak.scm)：仓库任务入口。
- [configs/main/init-config.scm](./configs/main/init-config.scm)：安装系统用入口。
- [configs/main/system-config.scm](./configs/main/system-config.scm)：系统配置入口。
- [configs/main/home-config.scm](./configs/main/home-config.scm)：Home 配置入口。

### 2. 聚合方式

- `maak.scm` 会递归处理 `configs/main/*.scm` 中的 `(load "../...")`。
- 生成后的完整文件会放到 `tmp/`。
- 之后通过 `guix time-machine --channels=configs/channel.lock -- ...` 执行。

### 3. 基础数据源

- [configs/information.scm](./configs/information.scm)：用户名、channel lock、machine-id、Btrfs 子卷和持久化目录等全局事实来源。
- 修改用户名、持久化目录、Btrfs 子卷、channel 相关行为时，应优先检查这里是否已经被其他模块引用。

## 目录职责

### `configs/system/`

定义 `operating-system` 的组成部分，包括：

- 引导器、文件系统、内核、用户、系统包。
- `services.scm` 作为系统服务聚合器，再拆到 `services/*.scm`。
- `skeletons.scm` 负责 skeleton 文件。

如果是系统层变更，优先落在对应子模块，不要把逻辑直接堆回 `configs/main/system-config.scm`。

### `configs/home/`

定义 `home-environment` 的组成部分，包括：

- `package.scm`：用户级包集合。
- `services.scm`：Home 服务聚合器。
- `services/dotfile.scm`：将 `../dotfiles` 暴露给 Home，并附加若干 `configs/files/*` 生成的文件。
- `services/programs/*.scm`：按程序维护包或服务片段。

若某个应用已经由 `dotfiles/` 提供真实配置，优先改对应 dotfile；若需要让 Guix Home 安装、链接或生成它，再改 `configs/home/services/*.scm`。

### `configs/files/`

放静态模板、原始配置和需要 `computed-substitution-with-inputs` 的文件。适合：

- 需要把包的绝对路径注入模板。
- 不适合直接放进 `dotfiles/` 的生成式配置。

### `dotfiles/`

这里是用户空间配置树，最终由 Home 的 dotfiles 服务分发。修改时注意：

- 保持相对路径与目标家目录一致。
- 不要随意移动目录，否则 Home 链接路径会变化。
- `dotfiles/.config/emacs/` 是一个独立复杂子系统，有自己的 `AGENT.md`。

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

- 优先在最具体的模块中修改，而不是改聚合入口。
- 保持现有 `(load ...)` 风格和变量命名习惯，例如 `%services-config`、`%packages-list`。
- 新增程序配置时，同时考虑三处是否需要联动：
  - 包是否要加入 `configs/system/packages.scm` 或 `configs/home/package.scm`
  - 服务是否要加入 `configs/system/services*.scm` 或 `configs/home/services*.scm`
  - 配置文件是否要放到 `dotfiles/` 或 `configs/files/`
- 当 README 的结构描述过时，如有必要可顺手修正文档，但不要把错误结构继续复制进新文件。

### Don't

- 不要把生成出来的 `tmp/*.scm` 当成源码维护。
- 不要直接编辑子模块内容来规避仓库层问题，除非任务明确要求修改该子模块。
- 不要在根级 `AGENT.md` 里重复 Emacs 子树的细节说明；那部分应留给其局部 `AGENT.md`。
- 不要假设 README 中的文件名一定存在，先核对实际路径。

## 验证建议

能做局部验证时，优先局部验证：

- Scheme 结构检查：至少重新阅读被修改模块与其聚合入口，确认变量名、`load` 路径和括号层级一致。
- 任务流验证：涉及装配逻辑时，优先考虑是否需要执行 `maak home` 或 `... system`。
- dotfiles 验证：确认路径是否仍然与目标家目录一致。

如果当前环境缺少 `guix`、`maak` 或相关依赖，明确说明未执行实际重配置即可，不要伪称已验证。

## 面向 AI 的决策规则

- 用户提到“系统配置”时，通常先看 `configs/system/`。
- 用户提到“ 用户/软件 配置”时，通常先看 `configs/home/` 与 `dotfiles/`。
- 用户提到“为什么最终配置里出现某个字段”时，沿着 `configs/main/*.scm` 的 `load` 链回溯。
- 用户提到 Emacs 时，先切换到 [dotfiles/.config/emacs/AGENT.md](./dotfiles/.config/emacs/AGENT.md) 的规则集。

## 已知风险点

- `setup/` 与 `dotfiles/.local/share/fcitx5/rime` 是子模块，操作前先确认任务是否真的要求改动它们。
