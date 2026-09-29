<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# gen-partial.scm — 生成「单频道刷新」的临时 channels 文件

- 源码：`tools/gen-partial.scm`
- 部署：不部署（blueprint.scm 以仓库内路径直接调用）
- 调用方：`blueprint.scm` 的 `%partial-channels-file`，由 `blue update --guix --channel <名> [--commit <commit>]` 触发

## 用法

```bash
guix repl tools/gen-partial.scm TARGET OUT-FILE [COMMIT]
# TARGET   要刷新的频道名（须在 channel.scm 中声明）
# OUT-FILE 输出的临时 channels 文件路径
# COMMIT   可选：目标频道 pin 到该 commit；不传则保持 channel.scm 的可变定义
```

必须以仓库根为工作目录运行（脚本按 `getcwd` 定位 `source/channel.scm` 与 `source/channel.lock`）。

## 依赖

- 必须在 `guix repl` 里跑：加载频道文件需要 `(guix channels)`、`(guix openpgp)` 等 guix 自带模块。

## 工作原理

Guix 的 channels 文件原生支持「pin 混搭」：带 `(commit ...)` 的频道固定在该 commit，不带的跟随 branch 最新。单频道刷新 = 生成一份临时 channels 文件：

1. 分别在干净模块里加载 `channel.scm`（可变定义）与 `channel.lock`（锁定版本）；
2. 按 `channel.scm` 的频道顺序合并：目标频道用 `channel.scm` 定义（给了 COMMIT 就以 `(inherit ...)` 函数式覆盖 commit 字段）；其余频道用 `channel.lock` 的锁定版本，lock 缺席的回退 `channel.scm` 定义；
3. `pretty-print` 出 `(list <channel->code>...)` 到 `OUT-FILE`。

调用方随后照常 `time-machine describe` 产出新的完整 lock（见 `docs/emergency-blue.md` §8 的 update 门禁流程）。

## 设计决策与不变量

- **为什么必须走 `guix repl` 子进程**：blue 自身的 Guile 环境缺 `(guix openpgp)`、`(gcrypt hash)` 等模块，`channel.lock`/`channel.scm` 里的 `openpgp-fingerprint` 宏展开会报 unbound variable——必须借用 guix 的 Guile 环境。
- **`%load-channels` 在 fresh module 求值**：`save-module-excursion` + `make-fresh-user-module`，并显式 `module-use!` 引入 `(guix channels)` 与 `(guix openpgp)`——后者提供宏展开期需要的 `openpgp-fingerprint->bytevector`。
- 目标频道名不在 `channel.scm` 声明列表时打「未知频道 + 可用清单」并退出 1。

## 变更记录

- 2026-09-29：注释迁入本文档；修正文件头已过时的调用方说明（原写「tools/update-locks.py / legacy blue」，该文件在仓库中并不存在，实际调用方是 blueprint.scm 的 `%partial-channels-file`）。行为不变。
