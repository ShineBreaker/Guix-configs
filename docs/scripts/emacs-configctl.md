<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# configctl — `emacs.org` 操纵工具（bash wrapper + elisp 引擎）

`dotfiles/mutable/emacs/.config/emacs/scripts/configctl` + 同目录 `configctl.el` · 部署到 `~/.config/emacs/scripts/`（mutable，stow 直链，改源即时生效）· 调用方：agent 与用户手动调用

本文是**契约正本**（命令行为、状态透传、锁、隔离、统计口径）；`~/.config/emacs/AGENTS.md` §2 只保留导航视角的子命令表与 8 大配置域编排。

## 用法

```bash
configctl map               # 结构总览：CUSTOM_ID、行号、代码行数、noweb ref
configctl show <ID>         # 提取一个功能子树全文
configctl locate <ID|REF>   # 定位块行号区间（CUSTOM_ID）或 noweb ref 的定义 / 组装位置
configctl tangle            # emacs.org → main.el（仓库内真实产物，gitignore）
configctl check             # 轻量结构检查，不写真实 main.el
configctl help | -h | --help
```

`show` 先按 `CUSTOM_ID` 精确匹配，未命中才退到**标题**的大小写无关子串模糊匹配，且必须唯一命中，否则报 `unknown feature: <q>` 或 `ambiguous feature <q>: <候选 ID 列表>`。`locate` 不做模糊：先 `CUSTOM_ID` 精确匹配，未命中即当作 noweb ref 名（先列定义块行号区间，再列所有引用它的组装块），两者都不中报 `unknown ID or noweb ref: <q>`。无参数、`help`、`--help`、`-h` 打用法；参数个数不对也打用法再报错。

## 实现与约束

- **wrapper 三件事**：`flock -x /tmp/custom-config-configctl-${UID}.lock` 串行化并发调用（锁住整个 emacs 进程）；`emacs --batch -Q --script "$root/scripts/configctl.el" "$@"`——`-Q` 纯净环境与部署 Emacs 隔离，`--batch` 不触达运行中的 daemon（与 `emacsclient` 路径无关）；状态透传与清理。
- **状态透传**：elisp 在 `condition-case` 兜底后把退出码（正常 0、`error` 分支 1）写进环境变量 `LITERAL_CONFIGCTL_STATUS_FILE` 指向的文件，并以同值 `(kill-emacs status)` 结束。wrapper 用 `mktemp` 造该文件、先写入 `1` 作默认值、`trap 'rm -f "$status_file"' EXIT` 保证任何退出路径都清理，最后「文件内容是纯数字就 `exit` 它，否则退回 emacs 的退出码」；`set -euo pipefail` 下 emacs 自身非零退出会让脚本就地终止，由 EXIT trap 兜底清理。
- **引擎解析 org AST 而非正则**：`find-file-noselect` + `org-mode`，全部统计基于 `org-element-parse-buffer`；块索引只收 `emacs-lisp` 块与带 `#+name` 的任意语言数据块。
- **`check` 的统计口径是 `emacs.org` 结构的回归哨兵**，输出固定为：

  ```text
  OK: %d source blocks, %d noweb refs, %d forms, %d definitions, %d which-key desc keys, %d data tables
  ```

  六个数依次为：纳入索引的 src 块数、noweb ref 定义数、对**隔离 tangle 产物**读出的顶层 form 数与 `def*` 定义名数（`defun` / `defmacro` / `defsubst` / `defvar` / `defvar-local` / `defconst` / `defcustom` / `defface`，重名即报错）、`data/which-key-zh.el` 全局描述表的键数、`data/*.el` 中 `setq` 字面量表的个数。数量变动即结构漂移，应评估影响而非改数字。

- **`check` 全程不写真实 `main.el`**：把 `emacs.org` 复制到临时目录再 tangle，`unwind-protect` 里删掉临时目录——纯只读校验，仓库有未提交改动时也能安全跑。
- **`check` 的结构门禁**：全局 `#+PROPERTY: header-args` 契约行必须原样存在；8 个配置域的 `CUSTOM_ID` 顺序固定且无重复；不得出现 `(require 'custom-…` / `(provide 'custom-…` / `:tangle lisp/` 这类多产物架构残留；noweb ref 必须 `:tangle no`、**恰好被组装一次**、不跨域重复定义、不得有未定义引用；被引用的 `#+name` 数据块也必须 `:tangle no`。
- **which-key 描述表必须是字面量 `setq`**：只静态解析 `(setq custom:which-key-description-spec '(…))`，不加载文件；表缺失或值不是 quoted 字面量时直接报错，避免门禁静默失效。**自有键与数据表双源注册会让 which-key 替换链与帮助分组各自漂移**，双源键门禁要求 `custom/bind` 声明键与数据表键的交集为空——自有键的描述只写在声明处，数据表只承担内置/第三方键。`data/*.el` 各表由 `assoc` 首命中取用，同键重复的后续条目是永不生效的死条目，故按表拦重复键。

## 排障

报错一律以 `ERROR: <message>` 打到 stderr 并以退出码 1 结束 wrapper。常见门禁消息与含义：

| 消息                                                                                    | 含义                                              |
| --------------------------------------------------------------------------------------- | ------------------------------------------------- |
| `duplicate CUSTOM_ID: <id>` / `domain order changed: [...]`                             | 8 大配置域的 ID 重复或顺序被改                    |
| `noweb ref <r> must be assembled exactly once (found <n>)` / `undefined noweb ref: <r>` | noweb 组装点数量不对，或引用了未定义 ref          |
| `which-key 全局描述表存在 <n> 个双源键`                                                 | 描述在 `custom/bind` 与数据表各写了一遍，必须选边 |
| `<file>: <var> 的键 <k> 重复`                                                           | `data/*.el` 同表内重复键                          |
| `global emacs-lisp header contract changed`                                             | emacs.org 头部 `#+PROPERTY: header-args` 行被改   |
