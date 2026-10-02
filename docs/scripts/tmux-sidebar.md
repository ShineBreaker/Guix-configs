<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# tmux-sidebar — 侧栏渲染子系统（Guile daemon + 模块）

`dotfiles/immutable/terminal/.config/tmux/scripts/sidebar-render.scm` 与 `sidebar/*.scm` · immutable → `~/.config/tmux/scripts/`（改后须 `blue home`） · `sidebar-toggle`：建 floating pane 跑 daemon，经 FIFO 触发 signal / click / toggle-group

## 接口

```bash
sidebar-render.scm daemon        # 长驻：FIFO 收事件 + 聚焦时读 stdin 键盘
sidebar-render.scm render        # 单次渲染到 stdout（测试 / 调试）
sidebar-render.scm --as-library  # 仅 load 定义不运行（供其他脚本引用）
```

非法模式打 `usage: sidebar-render.scm daemon|render` 到 stderr 并 `exit 2`。

## 模块分工

| 文件         | 层  | 职责                                                     |
| ------------ | --- | -------------------------------------------------------- |
| `text.scm`   | 叶  | ANSI 常量、pane 字段访问、文本宽度/截断/填充/居中、路径处理 |
| `info.scm`   | 中  | git HEAD/分支探测与 `/proc` 子进程 argv 解析（均带缓存） |
| `layout.scm` | 中  | 折叠键派生、pane→window→group→session 聚合、布局行与样式 |
| `input.scm`  | 顶  | 键盘光标导航、按键解析（cbreak）、FIFO 事件循环          |

**分层是契约**：`text` 不依赖兄弟模块；`info` / `layout` 只依赖 `text`；`input` 反向依赖主文件的状态机（`handle-action` / `render-current!` 等）。`sidebar-render.scm` 是 owner，定义渲染状态机与 `run-daemon`，再 `load` 四个模块——加模块时维持此 DAG。

`layout.scm` 是纯计算，只写 `current-output-port`，不查 tmux；tmux 访问集中在 `collect-state`。

## 设计决策与不变量

- **单次查询契约**：每次刷新只跑一次 `tmux list-panes`，上下文、宽度与折叠状态全从那一份快照取，不跨进程缓存、不重复查询。
- **缓存**：git 探测与 `/proc` argv 解析都带时间戳缓存，daemon 渲染热路径不做系统调用。
- **FIFO 名双端同步**：`tmux-sidebar-$UID-$pane_id.fifo`，与 `sidebar-toggle` 的 `fifo_path()` 必须保持同一约定。
- **模块加载路径同理**：部署位置 `$HOME/.config/tmux/scripts/sidebar/` 优先，回退源树同目录——immutable 下主文件是独立 store 单文件项，`current-filename` 的 dirname 落在 `/gnu/store`（那里没有 `sidebar/`）。
- **tmux option 读写分工**：daemon **只读** `@sidebar_*` 消费状态，所有写入归 `sidebar-toggle`（见 [sidebar-toggle.md](sidebar-toggle.md)）。侧栏作为浮动 pane 显示，宽度只是渲染依据。
- **事件分级**：FIFO 行分「变更型」（`toggle-group` / `click`）与「仅刷新」（`refresh`）。变更型事件只触发状态刷新，**绝不触发重绘**——点击命中检测依赖只在真正重绘时更新的动作表，必须与用户当前所见屏幕一致。
- **退出护栏**：daemon 顶层用 `guard` 接全部异常写 stderr 后 `exit 1`，不崩溃；pane 销毁 / EOF 时清理 FIFO 与光标。

## 排障

- `guild compile` 报「possibly unbound variable」：这是**动态 `load` 设计的固有噪声**，不是真错误——各模块互相引用主文件后定义的顶层变量，静态编译期看不到定义顺序。
- daemon 起不来且 stderr 无输出：先确认 FIFO 路径与 `sidebar-toggle` 侧一致，再看 `sidebar-toggle signal` 是否能在 `~/.config/tmux/scripts/` 下找到本文件。