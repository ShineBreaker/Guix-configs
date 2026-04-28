<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# 终端 IDE 功能说明

## 功能目标

本方案提供一个基于 `tmux + tmuxifier + broot + helix` 的终端 IDE 工作区，目标是尽量贴近 VSCode 的三栏心智模型：

- 左侧：`broot` 目录树
- 主区：`helix`
- 底部：shell 终端

### 启动

部署后，在任意项目目录中执行：

```bash
termide
```

`termide` 现在是 Guix Home profile 提供的命令。首次启动会创建 `termide` tmux 会话，再次执行会直接切换或附着到该会话。

## 工作流

### 进入 IDE

```bash
cd /path/to/project
termide
```

### 在左侧文件树中打开文件

- `Enter`
- `Ctrl-E`

这两个动作都会把当前文件发送到右侧 Helix，并自动聚焦到编辑器 pane。这比之前更接近 VSCode 里在左侧资源管理器打开文件后的行为。

如果想保留光标在左侧目录树：

```text
Ctrl-O
```

### 让底部终端跳到当前目录

在 `broot` 中按：

```text
Ctrl-T
```

底部终端会切到当前文件所在目录；如果当前选中的是目录，则直接切到该目录。

## 鼠标行为

`tmux` 侧启用了鼠标增强，重点是这几类行为：

- 点击 pane 会直接切换焦点
- 可以直接拖动 pane 边界调整尺寸
- 在 pane 中滚轮向上时，如果当前程序没有接管该事件，tmux 会自动进入 copy mode 并滚动历史
- pane 顶部会显示 `Explorer`、`Editor`、`Terminal`，更容易在鼠标切换时确认当前区域

注意：

- `broot` 本身仍然是终端文件管理器，不会完全复制 GUI 资源管理器的点击语义
- 当前主要对齐的是 tmux 层面的 pane 切换、滚动和布局识别

## 依赖说明

该功能依赖这些包出现在 Home 环境中：

- `tmux`
- `tmuxifier`
- `helix`
- `broot`
- `tmux-xpanes`

## 备注

- 该布局默认会话名固定为 `termide`
- 布局根目录取启动 `termide` 命令时的当前目录
- `termide open <file>` 会默认切到编辑器 pane
- `termide open --no-focus <file>` 可保留在侧边栏
