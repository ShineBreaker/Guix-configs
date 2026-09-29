<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# tmux-sidebar — 侧栏渲染子系统（Guile daemon + 模块）

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/sidebar-render.scm` + `sidebar/{text,info,layout,input}.scm`
- 部署：`~/.config/tmux/scripts/`（immutable，改后需 `blue home`）
- 调用方：`sidebar-toggle`（创建 floating pane 跑 `sidebar-render.scm daemon`）；`sidebar-toggle signal/click/toggle-group` 经 FIFO 触发渲染

## 接口

```bash
sidebar-render.scm daemon        # 长驻：FIFO 收事件 + 聚焦时读 stdin 键盘
sidebar-render.scm render        # 单次渲染到 stdout（测试/调试）
sidebar-render.scm --as-library  # 仅 load 定义不运行（供其他脚本引用）
```

非法模式 → `usage: sidebar-render.scm daemon|render`（stderr）+ 退出非零。

## 模块分工

| 文件 | 职责 |
| ---- | ---- |
| `text.scm` | 基础工具：ANSI 常量、pane 字段访问、文本宽度/截断/填充/居中、路径处理。**leaf，不依赖兄弟模块** |
| `info.scm` | 外部状态采集：git HEAD/分支探测（带时间戳缓存）、`/proc` 子进程 argv 解析（带缓存）。依赖 `text.scm` |
| `layout.scm` | 折叠键派生、pane→window→group→session 聚合、布局行构造与样式输出。**纯计算**（仅写 `current-output-port`），不查 tmux |
| `input.scm` | 键盘光标导航、按键解析（cbreak）、FIFO 事件循环。反向依赖主文件的状态机（`handle-action`/`render-current!` 等） |

`sidebar-render.scm` 是 owner：定义渲染状态机与 `run-daemon`，`load` 进四个模块。

## 设计决策与不变量

- **分层契约**：`text` leaf、`info`/`layout` 中层、`input` 顶部反向依赖主文件——加模块时维持此 DAG。
- **缓存**：git 探测与 `/proc` argv 都带时间戳缓存，daemon 渲染热路径不做系统调用。
- **FIFO 名**：`tmux-sidebar-$UID-$pane_id.fifo`，与 `sidebar-toggle` 的 `fifo_path()` 双端同步。
- **退出护栏**：daemon 顶层接异常写 stderr 不崩溃，pane 销毁/EOF 时清理 FIFO 与锁。
- **tmux option 读写分工**：daemon 只读 `@sidebar_*` 消费状态；写入归 `sidebar-toggle`（见 sidebar-toggle.md）。

## 变更记录

- 2026-09-29：模块头注释精简 + 文档外移；`guild compile` 的「possibly unbound variable」告警是动态 load 设计的固有噪声（行为不变）。
