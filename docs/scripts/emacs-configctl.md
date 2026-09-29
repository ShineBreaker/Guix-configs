<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# configctl — emacs.org 操纵工具（Bash wrapper + Elisp 引擎）

- 源码：`dotfiles/mutable/emacs/.config/emacs/scripts/configctl` + `configctl.el`
- 部署：`~/.config/emacs/scripts/`（mutable，stow 直链即时生效）
- 调用方：agent/用户手动调用；Emacs AGENTS.md §2 定位流程

## 用法

```bash
configctl map               # 全部 CUSTOM_ID 清单：行号、代码量、noweb ref
configctl show <ID>         # 提取指定子树全文（支持唯一模糊匹配）
configctl locate <ID|REF>   # 定位块行号区间或 noweb ref 的组装位置
configctl tangle            # emacs.org → main.el
configctl check             # 静态检查：域顺序、noweb 依赖图、括号平衡等
configctl help | -h | --help
```

## 工作原理

wrapper（Bash）：

1. `flock -x /tmp/custom-config-configctl-${UID}.lock` 串行化并发调用。
2. `emacs --batch -Q --script scripts/configctl.el "$@"`——`-Q` 纯净环境，与部署 Emacs 隔离。
3. **状态透传 hack**：`set -e` 下 emacs 非零退出会中断脚本，wrapper 经临时文件 `LITERAL_CONFIGCTL_STATUS_FILE` 拿回 elisp 显式写的退出码，`trap … EXIT` 保证清理。

引擎（`configctl.el`）：解析 `emacs.org` 的 org-element AST，输出块清单/提取/定位/tangle/check。

## 设计决策与不变量

- **不触达运行中的 daemon**：全程 batch + `-Q`，与 `emacsclient` 路径无关。
- `locate` 同时认 `CUSTOM_ID` 与 noweb ref 名；`show` 的模糊匹配要求唯一命中。
- `check` 的统计口径（源块数、noweb ref、表单数、定义数、which-key 键、数据表）是 emacs.org 结构的回归哨兵。

## 变更记录

- 2026-09-29：注释压缩、未用解构变量改 `_owner`、docstring 转义修正（行为不变）。
