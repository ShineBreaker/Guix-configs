<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# retry — 命令失败自动重试 + sudo 保活

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/retry.fish`
- 部署：`~/.config/fish/functions/retry.fish`（immutable，改后需 `blue home`）
- 调用方：手动调用，如 `retry sudo apt update`；补全 `completions/retry.fish`

## 用法

```bash
retry <cmd> [args...]
```

最多重试 5 次；5 次失败后询问 `已重试 5 次失败。是否继续重试？(y/n)`，`y` 清零计数继续，其他输入 `return 1`。

## 工作原理

- 每次尝试 `eval $argv`（保留 shell 引号语义，与 toolbox `run_entry` 同理）。
- **sudo 保活**：`command -q sudo` 存在时 fork 一个后台 fish，每 60s `sudo -n true` 续期票据——耗时重试只需输一次密码；keeper 用 `kill -0 $fish_pid` 检测主 shell 存活，主 shell 退出后自灭。成功/放弃时 `kill` 掉 keeper。
- 已知边角：`Ctrl-C` 强杀会残留 keeper 进程（可 `jobs`/`kill` 清理）；`sudo -n` 无票据时静默失败不影响主流程。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
