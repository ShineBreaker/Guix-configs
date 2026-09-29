<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# blue — 蓝图执行入口（wrapper 层）

- 源码：`dotfiles/mutable/tools/blue/.local/bin/blue`
- 部署：`~/.local/bin/blue`（mutable，改源即时生效）
- 调用方：终端直接调用；`libexec/blue-update`、`libexec/blue-gc` 由本脚本分发；`blueprint.scm` 是蓝图本体（见 `docs/scripts/blueprint.md`）

## 用法

```bash
blue              # 交互菜单：标题 + 分类化命令列表 → 序号/命令名选择
blue <命令>       # 直接执行：exec blueprint.scm（锁定频道环境）
blue update|gc    # 拦截分发到 libexec/blue-update、libexec/blue-gc
```

## 依赖

`gawk`、`gum`、`zsh`、`guix`、`git`、`gpg`（menu 检查，`gpg` 仅作为 find 目标）、`stow`、`emacs`。

## 工作原理

- 从 `$0` 经 `readlink -f` 反推**仓库根**（`~/.local/bin/blue` 是 stow 软链，解链接后落在包目录，再向上定位 repo root）。
- **菜单依赖检查**（`menu_check`）分「必需」与「可选」两级：
  - 必需不满足 → 菜单不可用，但直接命令执行不受影响（blueprint 层自己校验环境）。
  - 可选（Stow 软链等）缺失只提示，不阻断。
  - Git 仓库检查：蓝图目录或其上游链路必须是 git 仓库（`git rev-parse --git-dir`）。
- **拦截即覆写**：上游 blueprint 也有 `update`/`gc`，此处按首参优先分发给 Guix 增强版 libexec 脚本；其余命令透传 `exec guix time-machine --channels=... -- guile -s blueprint.scm`（`REPO_ROOT`/`BLUEPRINT` 环境注入）。
- **拦截 gc 时的垃圾诱因**：`gc` 前置打印 `注意：stu 软链上游被 guix gc 视为垃圾根...` 等清单——gc 会误删 stow 链出的 home 文件上游 store 项，必须用户知情。

## 设计决策与不变量

- **`local` 全在函数内**：顶层只有 `_bin_dir`/`_libexec_dir`/`_repo_root` 三个变量；其余必须函数内 `local`，避免 menu_check 参数解析污染全局命名空间。
- **`menu_check` 的 git 探测经 shim 走真实 git**：测试 shim 的 `git` 会过滤 `--git-dir`，蓝图根的 git 探测依赖真实 git 可查，不能盲目 stub。
- **检查输出格式固定**：`[必需] name …` / `[可选] name …` / `[OK] Git 仓库`——测试与文档对齐此格式。
- **`update`/`gc` 用 `exec` 而非子进程**：分发后进程替换，信号（Ctrl-C）直达 libexec，wrapper 不残留在进程树上。

## 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `blue` 菜单灰显全部命令 | `menu_check` 必需项缺失（`gum`/`gawk`/`git`/`stow`/`emacs`） | 按打印的「缺失」清单安装 |
| 菜单提示「Git 仓库检查失败」 | repo 根解错（`$0` 链路异常）或 `.git` 不存在 | 检查 `~/.local/bin/blue` 软链目标、`pwd` 下 `git rev-parse` |

## 变更记录

无破坏性改动（本次重构只压缩注释）。
