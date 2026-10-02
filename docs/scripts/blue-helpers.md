<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# blue-helpers — 一次性构建助手

`tools/bootstrap.sh`（开带 blue 的临时 shell）、`tools/build-image.scm`（ISO 产物落地）、`tools/gen-partial.scm`（单频道刷新的临时 channels 文件）形态同源：都不部署、不产出口令（root 口令由人 `passwd` 设）、不常驻，只把一次性结果交回调用方；要么由 blue（`blueprint.scm`）调用，要么人工在仓库内跑一次。三者共享同一套前置信息，故合为一篇。

## 共享前置

- **环境**：三者都要一台已装 Guix 的机器；两个 `.scm` 必须跑在 guix 自带的 Guile 环境（`guix repl`）里，依赖 `(guix build utils)`、`(guix scripts system)`、`(guix channels)`、`(guix openpgp)`。blue 自身的 Guile 环境缺 `(guix openpgp)`、`(gcrypt hash)`，`channel.scm` 与 `channel.lock` 里的 `openpgp-fingerprint` 宏一展开就报 unbound variable——凡要把本地 channels 文件喂给 guix 的路径，都得经 `guix repl` 子进程借环境。
- **频道锁定**：guix 调用一律走 `guix time-machine --channels=source/channel.lock --` 才可复现，blue 侧由 `%guix` 统一套上。`bootstrap.sh` 自己锁；`build-image.scm` 的锁定来自调用方 `%guix`，脚本自身不锁、也不需要 sudo；`gen-partial.scm` 刻意不锁——它只读仓库里的 scm、只写临时文件，不调任何需要频道的 guix 命令。
- **`guix repl` 的 `--`**（实测）：不带 `--` 时后续选项由 guix 自己解析，`--image-type=iso9660` 会被 guix 当成自身选项报错退出 1；带 `--` 才原样转交脚本。所以 IMAGE-ARGS 惯例带 dash 的 `build-image.scm` 必须带 `--`；`gen-partial.scm` 的参数（频道名、路径、commit 哈希）不含 dash，两种写法实测 argv 相同——照各脚本 usage 串书写即可。
- **失败约定**：三个脚本自身出错一律写 stderr、非零退出。blue 侧统一经 `%run` 取退出码，非零即打印 `命令执行失败` 并以同码 `primitive-exit`（不抛异常、不打 backtrace），故 blue 的失败码就是脚本的失败码。

## bootstrap.sh — 干净 Guix 环境开带 blue 的临时 shell

`tools/bootstrap.sh` · 不部署（仓库内直接运行） · 人工执行：`README.org` 装机流程、[`docs/emergency-blue.md`](../emergency-blue.md) §3 恢复 blue

```bash
./tools/bootstrap.sh
```

全部动作是一条 `exec`：`exec guix time-machine -C "$CHANNEL_LOCK" -- shell -m "$MANIFEST"`，其中 `$CHANNEL_LOCK` 是 `source/channel.lock`，`source/manifest.scm` 的内容只有 `("blue")`。`exec` 替换当前 shell 进程，退出即回到原 ISO 环境，不污染全局 profile。

- 前置：已用官方 Guix ISO 启动，或已完成 `guix system install`；脚本自检 `guix`、`source/channel.lock`、`source/manifest.scm`，任一缺失走 `die`——`bootstrap: 错误: …` 写 stderr、退出 1。
- 仓库根取 `BASH_SOURCE[0]` 的父目录，不依赖调用 cwd；与 `gen-partial.scm` 靠 `getcwd` 定位仓库根正好相反。
- 职责到此为止：不分区、不动盘、不跑 `blue init`——装机后续必须人工执行。恢复 blue 的完整步骤见 [`docs/emergency-blue.md`](../emergency-blue.md)，本篇不复述。
- 首次运行较慢：要克隆并构建频道。

## build-image.scm — guix system image 产物落地

`tools/build-image.scm` · 不部署（`blueprint.scm` 以仓库内路径调用） · `blueprint.scm` 的 `build-iso-command`，即 `blue build-iso`

```bash
guix repl -- tools/build-image.scm DST [IMAGE-ARGS]...
# 例：`blue build-iso` 实际执行的形状（time-machine 前缀由 %guix 补上）：
#   guix time-machine --channels=source/channel.lock -- repl -- \
#     tools/build-image.scm dist/jeans-desktop-20260929.x86_64-linux.iso \
#     tmp/live-iso-desktop.scm --image-type=iso9660
```

`DST` 是产物落点，`IMAGE-ARGS` 原样 `apply` 给 `guix-system "image"`（通常是一个 OS 定义文件加 `--image-type=`）。参数个数不符就打 usage 到 stderr、退出 1。

- **stdout 是隐式契约**：脚本捕获 `guix system image` 的 stdout，`string-trim-both` 后把整段当作 store 路径再 `file-exists?`。上游若改成多行输出，这里会静默拷错文件——升级 guix 后值得复核。
- 拷贝前 `mkdir-p` 父目录，拷完 `make-file-writable`（store 副本只读，改可写供后续签名/读取）。
- store 路径不存在时静默结束：真失败会由 guix 非零退出提前中止脚本。
- 变体枚举、ISO 命名、tangle 编排都在 `blueprint.scm` 的 `build-iso` 一侧，本脚本只做「跑 image → 拷产物」。

## gen-partial.scm — 单频道刷新的临时 channels 文件

`tools/gen-partial.scm` · 不部署（`blueprint.scm` 以仓库内路径调用） · `blueprint.scm` 的 `%partial-channels-file`，即 `blue update --guix --channel <名> [--commit <commit>]`

```bash
guix repl tools/gen-partial.scm TARGET OUT-FILE [COMMIT]
```

- **必须以仓库根为 cwd 运行**：脚本按 `getcwd` 拼出 `source/channel.scm` 与 `source/channel.lock`，换个目录跑就是在读别的路径——与 `bootstrap.sh` 自推导仓库根相反。
- **必须走 `guix repl` 子进程**：理由见「共享前置」。
- 合并顺序按 `channel.scm` 的频道顺序（不是 lock 顺序）：目标频道取 `channel.scm` 定义（给了 `COMMIT` 就以 `(inherit …)` 覆盖成 pin 到该 commit），其余频道取 `channel.lock` 的锁定版本，lock 里缺席的回退 `channel.scm` 定义。
- `TARGET` 不在 `channel.scm` 声明的频道里 → 打印「未知频道 + 可用频道清单」到 stderr、退出 1。
- 产物写到 `OUT-FILE`（先 `mkdir-p` 父目录），成功时 stdout 打印一行摘要。调用方接着拿它跑 `guix time-machine --channels=<该文件> -- describe --format=channels`，输出原子写回 `source/channel.lock`。
- dry-run 下 `%partial-channels-file` 不生成临时文件，直接复用 `channel.scm` 原件并打一行 `[预演]`；故虽然调用处给 `%run` 传了 `#:real? #t` 逃生口（其语义是 dry-run 仍真跑），当前路径并不会真的执行本脚本。

## 变更

- 2026-10-03：三篇合并为本文件，`docs/scripts/bootstrap.md`、`docs/scripts/build-image.md`、`docs/scripts/gen-partial.md` 已删除；脚本头注释的文档指针按 CONVENTIONS §2 改指本篇对应小节。
- `gen-partial.scm` 修正文件头已过时的调用方说明：原写 `tools/update-locks.py / legacy blue`，该文件在仓库中并不存在，实际调用方是 `blueprint.scm` 的 `%partial-channels-file`。
