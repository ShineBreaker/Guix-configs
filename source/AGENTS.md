# source/ — Guix 配置源目录

本目录包含 Guix System / Guix Home 的 Scheme 源与 Org 文档。AI 助手在修改此目录前应先阅读本文件。

## 目录结构

```
source/
├── AGENTS.md          # 本文件
├── channel.scm        # 频道定义（URL/branch 以 .scm 源码为准）
├── channel.lock       # 锁定的频道版本（由 maak update 自动生成并 git commit -S，不要手动编辑）
├── information.scm    # 全局变量（username、%data-dirs、%btrfs-subvolumes、guix-channels）
├── config.org         # ★ 唯一的 Org 配置源（system + home 全部 Noweb 拼合）
├── files/             # 静态模板文件（见下方「files/ 模板系统」一节）
└── nix/               # 独立的 Nix home-manager 配置（与 Guix 配置并存，不互通）
```

> **结构说明**：
> - `source/configs/` 子目录已废弃；`system-config.org` + `home-config.org` 已合并为单一 `source/config.org`
> - `source/files/` 仅用作需要路径注入的静态模板（其余 dotfile 都放 `dotfiles/enable/<app>/`）

## 构建管线

```
source/config.org
        │
        ▼  maak rebuild → Emacs org-babel-tangle（Noweb 拼合）
tmp/config.scm
        │
        ▼  guix time-machine --channels=source/channel.lock system reconfigure
单一 reconfigure：operating-system 同时声明 guix-home-service（含 home-environment）
```

要点：
- `config.org` 是**唯一** Org 源文件
- `maak rebuild` 自动完成 tangle → 括号检查 → reconfigure → `guix locate --update`
- `MAAK_DRY_RUN=1 maak rebuild` 仅构建一次不写入系统

## config.org 结构（自上而下）

1. **模块导入**：`modules` 块（system-modules + home-modules）
2. **系统配置**：*系统配置* 章节（内含 Agent 指引）
   - Bootloader、FileSystems、Kernel、Packages、Services、Skeletons、Users
3. **用户配置**：*用户配置* 章节（内含 Agent 指引）
   - Packages（desktop / terminal / devtools / user）、Services、Environment、Font
4. **dotfile-services**：在 *用户配置* → *dotfiles 管理相关服务* 段
   - 通过 `home-dotfiles-service-type`（`(layout 'stow)`）分发 `dotfiles/enable/<app>/`

## Org Noweb 机制

`config.org` 使用 Org Mode Noweb 拼合代码块：

- `#+NAME: ref` 为代码块命名
- `<<ref>>` 在其他代码块中引用已命名的内容
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标
- 最终由 `emacs --batch org-babel-tangle` 展开为完整 `tmp/config.scm`

> `<<ref>>` 是 Org Mode 语法，**不是** Scheme 原生功能。不要尝试在 Scheme 解释器中执行 `config.org`。

## Agent 专区（必须先读）

`source/config.org` 头部包含两段 Agent 指引：

1. **系统配置 → Agent 指引**（约 line 41 起）：系统层职责边界、关键组件说明、文件系统架构、修改约定、决策规则
2. **用户配置 → Agent 指引**（约 line 1003 起）：Home 配置职责、dotfiles 管理规则、新增应用配置流程、修改约定、决策规则

**修改 `config.org` 前必须先读完这两段。**

## 全局变量（`information.scm`）

被 `config.org` 顶部通过 `(load "../source/information.scm")` 加载。

| 变量                 | 说明                                                              |
| -------------------- | ----------------------------------------------------------------- |
| `username`           | 主用户名（`"brokenshine"`）                                       |
| `fixed-machine-id`   | 基于 `username` 的 MD5                                            |
| `%data-dirs`         | bind-mount 持久化的用户子目录（XDG + dotfile 状态）              |
| `%btrfs-subvol-data` | 数据分区子卷路径                                                  |
| `%btrfs-subvolumes`  | Btrfs 子卷 → 挂载点映射                                            |
| `guix-channels`      | `(include "./channel.lock")` — 锁定频道列表                       |

> 变更前应同时检查 `config.org` 各代码块对这些变量的引用是否需要同步调整。

## files/ 模板系统

`source/files/` 存放**需要路径注入**的静态模板文件，由 `home-files-service-type` 直接部署。当前文件：

```
source/files/
├── nftables.conf      # 防火墙规则
├── rounded.qss        # Qt 圆角样式
├── zed.json           # Zed 编辑器配置
└── skel/
    └── .config/
        └── mihomo/
            └── config.yaml
```

- **路径注入语法**：`&&bin/foo&&`（替换为对应 Guix 包的绝对路径）
- 注入机制：rosenthal 频道的 `computed-substitution-with-inputs`（参见 `config.org` 的「区别对待某些配置文件」段）
- **不要把无需路径注入的 dotfile 放进 `source/files/`**；纯配置文件请放 `dotfiles/enable/<app>/`

## 频道管理

- `channel.scm`：可编辑，定义使用的频道和分支（URL 以此为准）
- `channel.lock`：自动生成，不要手动编辑
- `information.scm` 通过 `(include "./channel.lock")` 加载锁定版本
- 更新流程：编辑 `channel.scm` → `maak pull` → `maak update`

## maak 命令（与本目录相关）

完整列表见根目录 `AGENTS.md`：

```bash
maak rebuild               # tangle + 括号检查 + reconfigure + locate --update
MAAK_DRY_RUN=1 maak rebuild # 仅构建不写入
maak check                 # 仅括号平衡检查
maak tangle                # 仅导出 Org
maak update                # 更新 channel.lock + git commit -S
maak pull                  # guix pull
```

<critical>
**Do**：
- 修改前先读 `config.org` 头部的两段 Agent 指引
- 修改后用 `maak check` 做括号检查，再用 `MAAK_DRY_RUN=1 maak rebuild` 做完整 dry-run
- 优先修改 `dotfiles/`；只有需要 Guix Home / Guix System 介入时才改 `config.org`
- 能用 Home 解决的就不要升级到 System（保持系统层最小化）

**Don't**：
- 不要手动编辑 `tmp/config.scm`（自动生成）
- 不要恢复 `source/configs/system-config.org` / `home-config.org`（已合并）
- 不要在 org 文件中使用 Scheme 原生不支持的语法（`<<ref>>` 是 Org Noweb）
- 不要把 `niri.kdl` 等不存在于 `source/files/` 的文件名写进文档（实际仅有 `nftables.conf`、`rounded.qss`、`zed.json`、`skel/`）
</critical>

## 修改约束

- `config.org` 是唯一 Org 源，**不要**新建第二个 org 配置文件
- 头部代码块（全局变量、文件系统、内核）会同时影响 system 和 home
- 启动时序敏感的服务（tmpfs /home 重建、bind-mount 等）集中在 `config.org` 的 `filesystem-services` 块
- 新增 dotfile 子目录后必须更新 `dotfile-services` 的 `packages` 列表并 `maak rebuild`