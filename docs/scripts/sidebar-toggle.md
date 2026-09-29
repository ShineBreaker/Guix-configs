<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# sidebar-toggle — tmux 侧边栏 pane 生命周期与事件适配器

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/sidebar-toggle`
- 部署：`~/.config/tmux/scripts/sidebar-toggle`（immutable，改后需 `blue home`）
- 调用方：`tmux.conf` 的 `bind B` 与一组 `set-hook`（after-select-pane、window-layout-changed、window/session-renamed、after-new-window、window-unlinked、after-new-session、client-session-changed、after-select-window、client-attached/detached/active、client-resized）、鼠标 `MouseDown1Pane` 绑定、`attach-entry` 的 follow 步骤

## 用法

```bash
sidebar-toggle [toggle|follow|resized|signal|click|toggle-group|layout-changed]
```

无参默认 `toggle`；非法动作打印 usage + `exit 2`（hook 里经 `run-shell -b` 静默）。

| 动作 | 语义 |
| ---- | ---- |
| `toggle` | 按 `@sidebar_visible` 开/关当前 session 侧栏 |
| `follow` | session 变化后按需建立/更新侧栏 pane |
| `resized` | 客户端尺寸变化后校正 pane 宽度 |
| `signal` | 事件→FIFO 轻量通知，催 daemon 重渲染 |
| `click` | 鼠标事件转发 FIFO（y/坐标/pane/client 透传） |
| `toggle-group` | 折叠/展开当前分组 |
| `layout-changed` | 窗口布局变化后的侧栏对齐 |

## 工作原理

Bash 只做 pane 生命周期（创建/销毁/floating-pane 调整），渲染与交互全在长驻 Guile daemon（`sidebar-render.scm daemon`），经每 pane 独有 FIFO `${XDG_RUNTIME_DIR:-/tmp}/tmux-sidebar-$UID-$pane_id.fifo` 通信——**文件名必须与 `sidebar-render.scm` 的 `fifo-path` 一致**。

## 设计决策与不变量

- `@sidebar_visible` 是 **session 级**选项：清理只清本 session（`-s`），不能越权关别人的。
- `@sidebar_width` **只读不写**：初始宽度归 `tmux.conf` 拥有；曾把竞态假偏离持久化导致宽度漂移。
- 手动拖拽偏离（window 未变时宽度不符）保持现状但不回写 `@sidebar_width`。
- `flock -n 9` 保证 hook 风暴下事件串行；取不到锁直接丢弃（幂等可重发）。
- FIFO 写走 `exec {fd}<>` 非阻塞打开；无 reader 时静默跳过。
- `signal`/`click` 等写动作在锁外执行可重入；`toggle`/`follow` 等改 pane 的动作在锁内。

## 变更记录

- 2026-09-29：注释压缩外移到本文件（行为不变）。
