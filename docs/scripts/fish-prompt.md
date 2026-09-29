<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# fish_prompt — Fish 提示符

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/fish_prompt.fish`
- 部署：`~/.config/fish/functions/fish_prompt.fish`（immutable，改后需 `blue home`）
- 调用方：fish 每次渲染提示符时调用

## 工作原理

上游 fish 自带 "Informative" 提示符的定制版：

- root 用户：`user@host cwd# ` 单行。
- 普通用户：`[HH:MM:SS] user@host cwd [pipestatus]` + 换行 + `> ` 两行式；管道各段退出码经 `__fish_print_pipestatus` 展示。

## 设计决策与不变量

- `__fish_last_status` 必须 `set -lx` 导出——`__fish_print_pipestatus` 读的是导出变量。
- 普通用户分支显示 `$PWD` 全路径（非 `prompt_pwd` 缩写），root 分支沿用 `prompt_pwd`。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
