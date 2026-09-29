<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# block-list.el / block-extract.el / block-replace.el — Org 命名代码块读写工具

- 源码：`tools/block-list.el`、`tools/block-extract.el`、`tools/block-replace.el`
- 部署：不部署（blueprint.scm 以仓库内路径直接调用）
- 调用方：`blueprint.scm` 的 `%run-elisp`——`blue check` 用 block-list、`blue block-show` 用 block-extract、`blue block-replace` 用 block-replace

三个文件共用同一套正则风格与「with-temp-buffer + insert-file-contents」读入方式，可对照阅读。

## 用法

```bash
emacs --quick --batch --script tools/block-list.el    FILE
emacs --quick --batch --script tools/block-extract.el FILE NAME
emacs --quick --batch --script tools/block-replace.el FILE NAME BODY-FILE OUT-FILE
```

生产中由 `%run-elisp` 套上 `guix time-machine -C source/channel.lock -- shell emacs-minimal --` 后调用；`FILE` 固定为 `source/config.org`。

## 输出协议（blueprint.scm 消费，勿改）

- **block-extract**：stdout 三段——`lang\nnoweb|plain\n<body>`（body 已 trim 首尾换行）。未找到块打 `[ERROR]` 并以退出码 1 结束。
- **block-list**：一次遍历导出全部命名块，记录格式：

  ```
  >>>name=<n>\tlang=<l>\tnoweb=plain|noweb
  <body 各行>
  <<<
  ```

- **block-replace**：把 `FILE` 中 `NAME` 块的 body 换成 `BODY-FILE` 内容，结果写 `OUT-FILE`（**不回写输入文件**，由 blueprint 侧 `%write-file-atomically` 原子替换）；stdout 打 `lang=<lang>`，外层据此对 scheme 块做括号验证。未找到块打 `[ERROR]` 并退出 1。

## 工作原理

块定位用行首锚定正则而非完整 org parser：`^#+NAME: <name>$`（name 经 `regexp-quote` 转义）→ 下一行 `^#+begin_src <lang>` → body 至 `^#+end_src`。noweb 判定为 body 内含 `<<...>>`。

## 设计决策与不变量

- **协议是跨语言契约**：分隔符 `>>>` / `<<<` 避开 body 内任意文本；blueprint.scm 的 `%block-header-re` 与三个文件严格配对。改动协议必须同步 blueprint.scm——优先不动。
- **一次遍历**：block-list 单进程导全表，避免每块起一个 emacs。
- **不 find-file**：三个文件统一 temp buffer 读入——不激活 org-mode、不求值文件局部变量；block-replace 也只写 `OUT-FILE`。代价：temp buffer 没有 `buffer-file-coding-system`，写文件时显式绑 `coding-system-for-write` 为 `utf-8-unix`（输入恒为 UTF-8），否则非 UTF-8 locale（如 `LANG=C`）下写中文会回退到 locale 默认编码。
- **body 规范化**：extract/list trim 首尾换行；replace 写回时 `string-trim-right` 后补一个换行，保证 round-trip 幂等。

## 故障排查

- `[ERROR] 未找到代码块`：确认 `#+NAME:` 行顶格且行尾无多余空白（正则要求行首起、行尾只允许空白）。
- 历史记录：`blue block-replace` 曾在旧版 time-machine 的 emacs-minimal 组合下报 `Symbol's value as variable is void: replaced`（见 hermes 技能库留痕）；当前锁定频道的 emacs-minimal 复测正常。若复发，先用直接 `--script` 调用隔离 wrapper 因素。

## 变更记录

- 2026-09-29：加 `lexical-binding: t`（规范要求）；block-replace 由 `find-file` 改为 temp buffer + `insert-file-contents`（与另两件统一、避免 mode/局部变量激活），并为 `write-region` 显式绑 `coding-system-for-write` 到 `utf-8-unix`（temp buffer 无 `buffer-file-coding-system`，非 UTF-8 locale 会写错编码）。输出协议与行为不变——block-list 全量导出、block-extract 抽取与 block-replace 无变化替换的 round-trip 在普通 locale 与 `LANG=C LC_ALL=C` 下均与旧版逐字节一致。
