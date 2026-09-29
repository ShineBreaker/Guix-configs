<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# run — 按目录构建文件派发

- 源码：`dotfiles/immutable/terminal/.config/fish/functions/run.fish`
- 部署：`~/.config/fish/functions/run.fish`（immutable，改后需 `blue home`）
- 调用方：手动调用 `run <args>`；补全 `completions/run.fish` 用同一套探测逻辑转发 `complete -C`

## 用法

按优先级探测当前目录文件并透传全部参数：

| 探测文件             | 派发命令        |
| -------------------- | --------------- |
| `maak.scm`           | `maak $argv`    |
| `blueprint.scm`      | `blue $argv`    |
| `justfile`/`Justfile` | `just $argv`    |

都不存在时报错 `run: 当前目录下未找到 maak.scm / blueprint.scm / justfile`（stderr）并 `return 1`。

## 设计决策与不变量

- 探测顺序固定（maak → blueprint → just），`run rebuild` 在本仓库等价 `blue rebuild`。
- 不做参数解析，全部透传；completion 用 `complete -C` 让 fish 按目标命令的规则补全。

## 变更记录

- 2026-09-29：注释压缩、`fish_indent` 规范化（行为不变）。
