<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# build-image.scm — guix system image 产物落地助手

- 源码：`tools/build-image.scm`
- 部署：不部署（blueprint.scm 以仓库内路径直接调用）
- 调用方：`blueprint.scm` 的 `build-iso-command`（`blue build-iso`，自动套 `guix time-machine` 锁定频道）

整条 ISO 管线的功能模型与设计权衡见 [`docs/iso-build.md`](../iso-build.md)（§0 管线图），本文件只记录脚本自身的契约。

## 用法

```bash
guix repl -- tools/build-image.scm DST [IMAGE-ARGS]...
# 例：guix repl -- tools/build-image.scm dist/jeans-desktop-20260929.x86_64-linux.iso \
#      tmp/live-iso-desktop.scm --image-type=iso9660
```

`DST` 为产物落点（如 `dist/<name>.iso`），`IMAGE-ARGS` 原样传给 `guix system image`（通常是一个 OS 定义文件加 `--image-type=`）。参数个数不符时打 usage 并以退出码 1 结束。

## 依赖

- 必须在 guix 的 Guile 环境（`guix repl`）内跑：需要 `(guix build utils)` 与 `(guix scripts system)`。
- 频道锁定由调用方负责（`blue build-iso` 经 `%guix` 套 `time-machine -C source/channel.lock`）；脚本自身不锁频道、不需要 sudo。

## 工作原理

三步：

1. `(apply guix-system "image" args)` 程序化生成镜像——等价于在 locked channel 里跑 `guix system image ARGS`；
2. `with-output-to-string` 捕获其 stdout，取末行 store 路径（`/gnu/store/...-iso9660-image`）；
3. 复制到 `DST`（`mkdir-p` 父目录）并 `make-file-writable`（store 副本只读，改成可写供后续签名/读取）。

store 路径不存在（构建失败）时静默结束——真实失败会以 guix 的非零退出提前中止脚本。

## 设计决策与不变量

- **只落地不编排**：构建编排、变体枚举、ISO 命名都在 `blueprint.scm` §8.5；本脚本只做「跑 image → 拷产物」。
- **stdout 契约**：依赖 `guix system image` 把产物路径打到 stdout——若上游改为多行输出，`string-trim-both` 之后可能不是纯路径，需复核。
- **等价上游实现**：与 Testament 的 `tools/build-image.scm` 等价（本仓库版加 SPDX 头）。

## 变更记录

- 2026-09-29：注释知识迁入本文档；新增参数个数检查——此前无参/错参时 `match` 无子句命中，静默退出 0，现在打 usage 并退出 1。
