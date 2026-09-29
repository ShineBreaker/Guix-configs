<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# screen-off — 倒计时后关闭显示器（niri）

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/screen-off.fish`
- 部署：`~/.config/fish/functions/screen-off.fish`（immutable，改后需 `blue home`）
- 调用方：手动调用；补全 `completions/screen-off.fish`

## 用法

```bash
screen-off        # 5 秒后熄屏（默认）
screen-off 30     # 指定秒数
screen-off a b    # 多于 1 个参数 → 用法 + return 1
```

倒计时期间 `Ctrl-C` 取消。

## 设计决策与不变量

- `sleep` 失败（如秒数非法）时**不熄屏**，把状态原样 `return $status` 给调用方——避免参数错误导致黑屏。
- 熄屏动作是 `niri msg action power-off-monitors`，需在 niri 会话内才有效。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
