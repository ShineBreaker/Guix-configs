<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# session-selector — 统一会话选择器

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/session-selector`
- 部署：`~/.config/tmux/scripts/session-selector`（immutable，改后需 `blue home`）
- 调用方：`conf.d/99-selector.fish`（foot/kitty 顶层终端启动时弹）

## 输出契约（stdout 单行）

| 输出 | 含义 |
| ---- | ---- |
| `tmux\|default` / `tmux\|new` / `tmux\|<name>` | 进 tmux 主会话 / 新建 / attach 命名会话 |
| `herdr\|default` / `herdr\|new` / `herdr\|<name>` | herdr 同构 |
| `shell` | 留普通 shell |
| `__header__` | 误选标题行 → 消费方重弹 |
| 空输出 | ESC/取消 → 留普通 shell |

kind 段允许含 `|`（分隔符即协议符），消费方用 `string split -m 1 '|'` 只切第一刀。

## 工作原理

fzf 列出候选（tmux 现有会话、herdr 现有环境、新建项、shell 项），选中项按上表输出单行。所有 tmux/herdr 查询容错——后端缺席时仍给出 shell/new 候选，不报错退出。

## 设计决策与不变量

- 契约字段、分隔符、空值语义见上表——**改任何一项必须同步改 `conf.d/99-selector.fish` 的消费端**。
- 标题/装饰行输出 `__header__` 哨兵而非空，区分「误选」与「取消」。

## 变更记录

- 2026-09-29：注释压缩外移到本文件与 `fish-conf-d.md`（行为不变）。
