<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# block-list.el / block-extract.el / block-replace.el — Org 命名代码块的枚举、抽取与替换

`tools/block-list.el` · `tools/block-extract.el` · `tools/block-replace.el` · 不部署（`blueprint.scm` 以仓库内路径调用）· 调用方：`blueprint.scm` 的 `%run-elisp`——`blue check` 用 block-list、`blue block-show` 用 block-extract、`blue block-replace` 用 block-replace

三件共用同一套正则风格与「temp buffer + `insert-file-contents`」读入方式，可对照阅读。

## 用法

```bash
emacs --quick --batch --script tools/block-list.el    FILE
emacs --quick --batch --script tools/block-extract.el FILE NAME
emacs --quick --batch --script tools/block-replace.el FILE NAME BODY-FILE OUT-FILE
```

生产中由 `blueprint.scm` 的 `%run-elisp` 调用：`%pipe->string` 套 `%emacs-command`（`time-machine --channels=<lock>` + `shell emacs-minimal` + `env -u` 五个 `EMACS*` 变量），`FILE` 固定为 `source/config.org`。

## 输出协议

协议面向 `blueprint.scm` 消费，**勿改**；改协议必须同步 `%block-header-re` 与 `%extract-all-blocks`（字段间是字面 TAB，分隔符 `>>>` / `<<<` 避开 body 内任意文本）。三件成功时退出码 0；未找到块时 stdout 打 `[ERROR] 未找到代码块 <name>` 并以退出码 1 结束。

| 工具 | stdout |
| --- | --- |
| `block-extract FILE NAME` | `lang\nnoweb\|plain\n<body>`（body 已 trim 首尾换行） |
| `block-list FILE` | 逐块三段记录：`>>>name=<n>\tlang=<l>\tnoweb=plain\|noweb` / body 各行 / `<<<` |
| `block-replace FILE NAME BODY-FILE OUT-FILE` | `lang=<lang>` |

`block-replace` **不回写输入文件**，只写 `OUT-FILE`；`source/config.org` 的落盘由 blueprint 侧 `%write-file-atomically` 原子完成。外层据 `lang=scheme` 决定是否追加 tangle + 括号验证。

## 实现与约束

- **块定位用行首锚定正则而非 org parser**：`^#+NAME: <name>$`（name 经 `regexp-quote` 转义、行尾只允许空白）→ 下一行 `^#+begin_src <lang>` → body 至 `^#+end_src`；noweb 判定为 body 内含 `<<...>>`。`block-list` 的 `#+NAME` 正则捕获组收集全部块（不 `regexp-quote`），只有 extract / replace 按名精确匹配。
- **三件统一 temp buffer + `insert-file-contents`，不用 `find-file`**：不激活 org-mode、不求值文件局部变量。
- **`block-replace` 必须显式把 `coding-system-for-write` 绑为 `utf-8-unix`**：temp buffer 没有 `buffer-file-coding-system`（只有 `find-file` 才有），`LANG=C` 等非 UTF-8 locale 下写中文会回退到 locale 默认编码。
- **body 规范化保证 round-trip 幂等**：extract 与 list trim 首尾换行；replace 写回时 `string-trim-right` 后补一个换行（空 body 也留一个空行），因此「抽取 → 原样替换」逐字节还原。
- **`block-list` 一次遍历导全表**，避免每块起一个 emacs 进程。

## 排障

`[ERROR] 未找到代码块` = `#+NAME:` 行必须顶格（正则以 `^` 锚定）、name 逐字符匹配（经 `regexp-quote`，无大小写或模糊）、行尾不得有多余内容（正则尾部只允许空白）。