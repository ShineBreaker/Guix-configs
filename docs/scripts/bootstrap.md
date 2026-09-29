<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# bootstrap.sh — 在干净 Guix 环境里开一个带 blue 的临时 shell

- 源码：`tools/bootstrap.sh`
- 部署：不部署（仓库内直接运行）
- 调用方：人工执行——`README.org` 装机流程、`docs/emergency-blue.md` §6 恢复 blue

## 用法

```bash
git clone https://codeberg.org/BrokenShine/Guix-configs
cd Guix-configs
./tools/bootstrap.sh
# 进入带 blue 的 shell 后按 README.org 继续（改 information.scm、blue init、passwd）
```

前置条件：已用官方 Guix ISO 启动，或已完成 `guix system install`；已克隆本仓库。脚本自检 `guix` 命令与两个输入文件，缺失时给出可操作报错而非 guix 的晦涩信息。

## 依赖

- `guix`（必须已安装——脚本面向「只有 guix」的干净机器）
- `source/channel.lock`（锁定频道版本）
- `source/manifest.scm`（引导环境的包清单，内容只有 `("blue")`）

## 工作原理

核心就一条命令：

```bash
exec guix time-machine -C "$CHANNEL_LOCK" -- shell -m "$MANIFEST"
```

`time-machine` 保证进入的频道版本与 `channel.lock` 完全一致；`shell -m` 按 manifest 开一个临时 profile shell，其中 `blue` 可用。仓库根由脚本自身位置（`tools/` 的父目录）推导，不依赖调用目录。

## 设计决策与不变量

- **职责到此为止**：脚本不分区、不动盘、不跑 `blue init`——后续装机步骤必须由人显式执行，避免一键脚本误伤机器。
- **临时 profile**：`guix shell` 默认是临时环境，`exec` 替换当前 shell 进程，退出即回到原 ISO 环境，不污染 ISO 的全局 profile。
- **blue 不依赖 blue 自身**：恢复 blue 的引导环境只需要 bash + guix + 本仓库（见 `docs/emergency-blue.md` §6）。

## 变更记录

- 2026-09-29：重构注释并迁入本文档；新增 `guix` 存在性检查与统一 `die`（错误带 `bootstrap:` 前缀、写 stderr）。行为不变。
