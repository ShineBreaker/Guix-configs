<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

本目录包含 Guix System / Guix Home 的源配置和 org 文档。AI 助手在修改此目录前应先阅读本文件。

## 目录结构

```
source/
├── channel.scm         # 频道定义（guix、jeans、nonguix、rosenthal）
├── channel.lock        # 锁定的频道版本（由 maak upgrade 更新，不要手动编辑）
├── information.scm     # 全局变量（username、%data-dirs、%btrfs-subvolumes 等）
├── configs/
│   ├── home-config.org     # Home 环境配置（tangle → tmp/home-config.scm）
│   └── system-config.org   # 系统配置（tangle → tmp/system-config.scm）
├── files/              # 静态模板文件（见下方说明）
└── nix/                # 实验性 Nix 配置
```

## Org Noweb 机制

配置文件使用 Org Mode 的 Noweb 功能进行代码块拼合：

- `#+NAME: ref` 为代码块命名
- `<<ref>>` 在其他代码块中引用已命名的内容
- 最终由 Emacs org-babel-tangle 将所有引用展开为完整 .scm 文件

**注意**：`<<ref>>` 是 Org Mode 语法，不是 Scheme 原生功能。在 org 文件中看到此类引用是正常的。

## 管线流程

```
source/configs/*.org
    → maak 调用 emacs --batch org-babel-tangle
    → tmp/*.scm（完整 Scheme 文件）
    → guix time-machine --channels=channel.lock system/home reconfigure
```

- `maak system`：tangle system-config.org → tmp/system-config.scm → guix system reconfigure
- `maak home`：tangle home-config.org → tmp/home-config.scm → guix home reconfigure

## Agent 专区

每个 org 配置文件的头部都有 `Agent 指引` 区域，包含：

- 该配置的职责边界和修改规则
- dotfiles 管理规则
- 新增应用配置流程
- 决策规则（Home vs System、dotfile vs org）

**修改前必须先阅读对应 org 文件的 Agent 专区。**

## 全局变量（information.scm）

此文件被两个 org 配置通过 `(load "../source/information.scm")` 加载。

| 变量                 | 说明                           |
| -------------------- | ------------------------------ |
| `username`           | `"brokenshine"`                |
| `fixed-machine-id`   | 基于 username 的 MD5           |
| `%data-dirs`         | 持久化用户数据目录列表         |
| `%btrfs-subvol-data` | 数据分区子卷路径               |
| `%btrfs-subvolumes`  | Btrfs 子卷 → 挂载点映射        |
| `guix-channels`      | 从 channel.lock 加载的频道列表 |

修改变量时注意：这些变量被 system-config.org 和 home-config.org 共同引用。

## files/ 模板系统

`source/files/` 存放需要路径注入的静态模板文件。

**路径注入语法**：`&&bin/foo&&`

- 模板文件中使用 `&&bin/foo&&` 标记需要替换的二进制路径
- 通过 Guix 的 `computed-substitution-with-inputs` 机制在构建时替换为实际包路径
- 示例文件：`niri.kdl`（窗口管理器配置）、`zed.json`（编辑器配置）、`nftables.conf`（防火墙规则）

## 频道管理

- `channel.scm`：频道定义（可编辑，定义使用的频道和分支）
- `channel.lock`：锁定的频道版本（由 `maak upgrade` 自动生成并 git commit）
- 不要手动编辑 `channel.lock`
- `information.scm` 通过 `(include "./channel.lock")` 加载锁定版本

<critical> 
**Do**：

- 在最具体的模块中修改
- 保持 `(load ...)` 风格
- 必要时修正 README
- 修改 dotfile 文件优先，只有需要 Guix Home 管理时再改 org 文件
- 能用 Home 解决就不用 System

**Don't**：

- 不要把 `tmp/*.scm` 当源码
- 不要直接编辑子模块，`emacs` 和 `termide` 除外
- 不要假设 README 文件名存在
- 不要在 org 文件中使用 Scheme 原生不支持的语法（`<<ref>>` 是 Org Noweb 功能）

</critical>

## 验证

- Scheme 语法：`guile --check <file>.scm`（注意 tangle 后的文件在 tmp/ 中）
- 完整构建：`maak system` 或 `maak home`
- 变量名和 `load` 路径一致性检查
