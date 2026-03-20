<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# 终端 IDE 功能说明

## 实现时间

- 2026-03-20 00:53:40 CST (+0800)

## 功能目标

本次实现的是一个基于 `tmux + tmuxifier + lf + helix` 的终端 IDE 工作区，布局思路对齐 Emacs 里的 `my/vscode-layout`：

- 左侧：`lf` 文件浏览器
- 中间主区：`helix`
- 底部：shell 终端

## 已写入的配置

- `configs/home/package.scm`
  - 新增 `lazygit`
  - 新增 `lf`
  - 新增 `tmux-xpanes`
- `dotfiles/.config/fish/functions/termide.fish`
  - 提供 `termide` 启动命令
- `dotfiles/.config/tmuxifier/layouts/vscode.session.sh`
  - 定义终端 IDE 会话布局
  - 左侧固定 30 列，底部终端固定 12 行，编辑器保留主区
- `dotfiles/.config/lf/lfrc`
  - 配置 `lf`
  - 将 `o` 和 Enter 绑定到打开动作
  - 在 tmux IDE 会话里会把文件送到主编辑器 pane

## 使用方法

### 部署

这次变更全部落在 Home 层，通常执行下面任一命令即可生效：

```bash
guix shell maak -- maak home
```

或：

```bash
guix shell maak -- maak rebuild
```

### 启动

部署后，在任意项目目录中执行：

```bash
termide
```

首次启动会创建一个名为 `termide` 的 tmux 会话，再次执行会直接切换或附着到该会话。

## 工作流

### 进入 IDE

```bash
cd /path/to/project
termide
```

### 在左侧文件树中打开文件

- `o`
- `Enter`

这两个键会将当前文件发送到主编辑器 pane 打开。

## 依赖说明

该功能依赖这些包出现在 Home 环境中：

- `tmux`
- `tmuxifier`
- `helix`
- `lf`
- `lazygit`
- `tmux-xpanes`

其中 `tmux`、`tmuxifier`、`helix` 原本已存在，本次补齐了缺失部分。

## 备注

- 该布局默认会话名固定为 `termide`。
- 布局根目录取启动 `termide` 命令时的当前目录。
- 如果在 tmux 外部运行，会直接附着到新会话。
- 如果在 tmux 内部运行，会切换到该会话。
