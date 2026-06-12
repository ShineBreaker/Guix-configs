# source/ — Guix 配置源目录

本目录包含 Guix System / Guix Home 的源配置和 org 文档。AI 助手在修改此目录前应先阅读本文件。

## 目录结构

```
source/
├── AGENTS.md          # 本文件
├── channel.scm        # 频道定义（以 .scm 源码为准，README URL 可能滞后）
├── channel.lock       # 锁定的频道版本（由 maak update 自动更新并 git commit，不要手动编辑）
├── information.scm    # 全局变量（username、%data-dirs、%btrfs-subvolumes 等）
├── config.org         # ★ 唯一的 org 配置源（包含 system + home 全部内容）
└── files/             # 静态模板文件（见下方「files/ 模板系统」一节）
```

> **结构说明**：`source/configs/` 子目录已废弃，原本拆分的 `system-config.org` + `home-config.org` 已合并为单一 `source/config.org`。该文件包含系统配置和用户配置的全部 Noweb 代码块，并统一 tangle 到 `tmp/config.scm`。

## 构建管线

```
source/config.org
        │
        ▼  maak apply → Emacs org-babel-tangle（Noweb 拼合）
tmp/config.scm
        │
        ▼  guix time-machine --channels=source/channel.lock system reconfigure
系统 + 用户环境（同一 .scm 文件同时声明 operating-system 和 home-environment）
```

> **要点**：
> - `config.org` 是**唯一**的 org 源文件，不再有 `system-config.org` / `home-config.org` 之分
> - 单一 `guix system reconfigure` 即可同时激活系统配置和用户配置
> - `maak apply` / `maak rebuild` 自动处理 tangle + 括号检查 + reconfigure

## Org Noweb 机制

配置文件使用 Org Mode 的 Noweb 功能进行代码块拼合：

- `#+NAME: ref` 为代码块命名
- `<<ref>>` 在其他代码块中引用已命名的内容
- 最终由 Emacs `org-babel-tangle` 将所有引用展开为完整 `tmp/config.scm`

> **注意**：`<<ref>>` 是 Org Mode 语法，不是 Scheme 原生功能。在 `config.org` 中看到此类引用是正常的，不要尝试在 Scheme 解释器中执行 org 文件。

## Agent 专区

`source/config.org` 头部包含 `Agent 指引` 区域（系统配置职责），涵盖：

- 系统配置的职责边界和修改规则
- dotfiles 管理规则
- 新增应用配置流程
- 决策规则（Home vs System、dotfile vs org）

**修改 `config.org` 前必须先阅读文件头部的 Agent 专区。**

## 全局变量（information.scm）

此文件被 `config.org` 顶部通过 `(load "../source/information.scm")` 加载。

| 变量                 | 说明                             |
|----------------------|----------------------------------|
| `username`           | `"brokenshine"`                  |
| `fixed-machine-id`   | 基于 username 的 MD5             |
| `%data-dirs`         | 持久化用户数据目录列表（含 bind-mount 目标） |
| `%btrfs-subvol-data` | 数据分区子卷路径                 |
| `%btrfs-subvolumes`  | Btrfs 子卷 → 挂载点映射          |
| `guix-channels`      | 从 channel.lock 加载的频道列表   |

> **修改约定**：`information.scm` 是 system 配置和 home 配置共享的全局变量源，变更前应同时检查 `config.org` 内部对各变量的引用是否需要同步调整。

## files/ 模板系统

`source/files/` 存放需要路径注入的静态模板文件。

**路径注入语法**：`&&bin/foo&&`

- 模板文件中使用 `&&bin/foo&&` 标记需要替换的二进制路径
- 通过 Guix 的 `computed-substitution-with-inputs` 机制在构建时替换为实际包路径
- 示例文件：`niri.kdl`（窗口管理器配置）、`zed.json`（编辑器配置）、`nftables.conf`（防火墙规则）

## 频道管理

- `channel.scm`：频道定义（可编辑，定义使用的频道和分支）
- `channel.lock`：锁定的频道版本（由 `maak update` 自动生成并 git commit）
- 不要手动编辑 `channel.lock`
- `information.scm` 通过 `(include "./channel.lock")` 加载锁定版本

## maak 命令（与本目录相关）

> 完整命令列表见根目录 `AGENTS.md`。本节只列出与 `source/` 强相关的命令。

```bash
maak check              # 仅括号检查（tangle 后验证 Scheme 语法平衡）
MAAK_DRY_RUN=1 maak apply    # 验证配置（不应用）
maak apply              # 应用 system + home 配置
maak rebuild            # apply + guix locate --update
maak update             # 更新 channel.lock + git commit -S
```

<critical>
**Do**：
- 修改前先读 `config.org` 头部的 Agent 专区
- 修改后用 `maak check` 做括号检查，再用 `MAAK_DRY_RUN=1 maak apply` 做完整 dry-run
- 优先修改 `dotfiles/`，只有需要 Guix Home/Guix System 介入时才改 `config.org`
- 能用 Home（用户配置）解决的，不要升级到 System（系统配置）

**Don't**：
- 不要手动编辑 `tmp/config.scm`（自动生成）
- 不要把旧的 `source/configs/system-config.org` / `home-config.org` 当作参考——它们已合并
- 不要在 org 文件中使用 Scheme 原生不支持的语法（`<<ref>>` 是 Org Noweb 功能）
- 不要假设 README 文件名存在
</critical>

## 修改约束

- `config.org` 是唯一的源，**不要**新建第二个 org 配置文件
- 修改 `config.org` 头部代码块（如全局变量、文件系统、kernel 配置）会同时影响 system 和 home
- 启动时序敏感的服务（tmpfs /home 重建等）集中在 `config.org` 的 `filesystem-services` 代码块
- 改完后用 `maak check` 验证括号平衡，确认无 syntax error 后再 `maak apply`
