<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# attach-entry — tmux 会话统一入口（attach-or-create 三步收敛）

- 源码：`dotfiles/immutable/terminal/.config/tmux/scripts/attach-entry`
- 部署：`~/.config/tmux/scripts/attach-entry`（immutable，改后需 `blue home`）
- 调用方：`conf.d/99-selector.fish`（会话选择器输出 `tmux|…` 后调用）

## 用法

```bash
attach-entry <session> [-n win] [-c dir] [--create]
```

- session 不存在且未给 `--create`：报错 + `exit 1`。
- `--create`：`tmux new-session -d` detached 创建（可选 `-n win`/`-c dir`），再走统一 attach。
- 非法参数：usage + `exit 2`。

## 工作原理

1. `has-session` 探测；缺失且 `--create` 时 detached 创建。
2. `set-option @sidebar_visible 1`（session 级）。
3. 尝试 `sidebar-toggle follow` 建立侧栏——**不阻塞 attach**，失败静默。
4. `exec tmux attach-session -t <session>`——attach 恒为最后一条，退出码透传（调用方凭它判断是否回选择界面）。

## 设计决策与不变量

- **绝不串联 tmux 命令链**（`a ; b ; c` 有竞态闪退），三步分开发送。
- `exec` 收尾是退出码透传契约的一部分，不能改成普通调用。

## 变更记录

- 2026-09-29：注释压缩（行为不变）。
