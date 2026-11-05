<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 文档索引

按用途分四块。改动仓库前先读根 `AGENTS.md`，它是硬约束；这里只放专题手册。

| 目录                         | 内容                                                                    |
| ---------------------------- | ----------------------------------------------------------------------- |
| [`operations/`](operations/) | 装机、应急部署、救援 chroot、Live ISO 构建                              |
| [`systems/`](systems/)       | 系统机制专题，如加密凭据入仓                                            |
| [`scripts/`](scripts/)       | 脚本手册，按 blue 本体、agent、终端、桌面分组                           |
| [`archive/`](archive/)       | 历史复盘。描述的是当时的环境，仅供追溯，当前实现以源码与 AGENTS.md 为准 |

## 常见入口

- 日常改配置：根 `AGENTS.md` 的「按任务找入口」。
- blue 命令与内部机制：[`scripts/repo/blueprint.md`](scripts/repo/blueprint.md)。
- 脚本写法规范：[`scripts/repo/CONVENTIONS.md`](scripts/repo/CONVENTIONS.md)。
- 系统重建失败、开不了机：[`operations/emergency-blue.md`](operations/emergency-blue.md) 与 [`operations/rescue-chroot.md`](operations/rescue-chroot.md)。
- 装机镜像：[`operations/iso-build.md`](operations/iso-build.md)。
