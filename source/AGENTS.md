# source/ — Guix 配置源目录

本目录包含 Guix System / Guix Home 的 Scheme 源与 Org 文档。AI 助手在修改此目录前应先阅读本文件。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
source/
├── files/
│   ├── skel/
│   │   └── .config/
│   │       └── mihomo/
│   ├── nftables.conf
│   ├── rounded.qss
│   └── zed.json
├── nix/
│   ├── configuration/
│   │   ├── 00-main/
│   │   │   ├── home.nix
│   │   │   └── packages.nix
│   │   └── programs/
│   │       ├── 00-main.nix
│   │       ├── code.nix
│   │       ├── hermes.nix
│   │       ├── nix.nix
│   │       └── prismlauncher.nix
│   ├── flake.lock
│   └── flake.nix
├── channel.lock
├── channel.scm
├── config.org
├── information.scm
└── manifest.scm
```

<!-- /structor -->

## 构建管线

```
source/config.org → blue rebuild → tmp/config.scm → guix system reconfigure
```

单一 reconfigure 同时应用 operating-system 与内嵌的 guix-home-service。

- `config.org` 是**唯一** Org 源
- `blue rebuild` 自动完成 tangle → 括号检查 → reconfigure → `guix locate --update`
- `blue --dry-run rebuild`：tangle + 括号检查真跑，reconfigure 短路

## config.org 结构

1. **模块导入**：`modules` 块
2. **系统配置**：Bootloader、FileSystems、Kernel、Packages、Services、Users
3. **用户配置**：Packages、Services、Environment、Font
4. **dotfile-services**：`home-dotfiles-service-type`（`layout 'stow`）分发 `dotfiles/enable/<app>/`

## Org Noweb 机制

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他块中引用（**不是** Scheme 原生语法，是 Org Mode 功能）
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标

## Agent 专区（必须先读）

`source/config.org` 头部包含两段 Agent 指引（`* System` 和 `* Home` 节）：

1. **System**：系统层职责边界、关键组件说明、修改约定、决策规则
2. **Home**：Home 配置职责、dotfiles 管理规则、新增应用流程、修改约定

**修改 `config.org` 前必须先读完这两段。**

## 全局变量（`information.scm`）

被 `config.org` 顶部通过 `(load "../source/information.scm")` 加载。

| 变量                 | 说明                                                |
| -------------------- | --------------------------------------------------- |
| `username`           | 主用户名（`"brokenshine"`）                         |
| `fixed-machine-id`   | 基于 `username` 的 MD5                              |
| `%data-dirs`         | bind-mount 持久化的用户子目录（XDG + dotfile 状态） |
| `%btrfs-subvol-data` | 数据分区子卷路径                                    |
| `%btrfs-subvolumes`  | Btrfs 子卷 → 挂载点映射                             |
| `guix-channels`      | `(include "./channel.lock")` — 锁定频道列表         |

> 变更前应同时检查 `config.org` 各代码块对这些变量的引用是否需要同步调整。

## files/ 模板系统

存放**需要路径注入**的静态模板，由 `home-files-service-type` 直接部署：

```
source/files/
├── nftables.conf      # 防火墙规则
├── rounded.qss        # Qt 圆角样式
├── zed.json           # Zed 编辑器配置
└── skel/              # 骨架文件
    └── .config/mihomo/config.yaml
```

- **路径注入语法**：`$$bin/foo$$` 替换为 Guix 包绝对路径（rosenthal 的 `computed-substitution-with-inputs`）
- **不要**把无需路径注入的 dotfile 放进此目录；纯配置文件请放 `dotfiles/enable/<app>/`

## 频道管理

- `channel.scm`：可编辑，定义频道和分支
- `channel.lock`：自动生成，**不要手动编辑**
- 更新流程：编辑 `channel.scm` → `blue pull` → `blue update`

## blue 命令（与本目录相关）

完整列表见根目录 `AGENTS.md`。常用：

```bash
blue rebuild               # tangle → 括号检查 → reconfigure → locate --update
blue --dry-run rebuild     # 构建验证不写入（tangle/括号检查真跑）
blue home                  # 仅 Home 层（含 dotfiles），不需 sudo
blue check                 # 括号平衡检查

# 块级编辑（修改单个 #+NAME: 块，避免读 2000 行 config.org）
blue block-show <name>                 # 提取块 body 到 tmp/block-<name>.scm（打印路径）
blue block-replace <name> <body-file>  # 替换 + 原子写回 + 验证
```

<critical>
**Do**：
- 修改前先读 `config.org` 头部两段 Agent 指引
- 优先改 `dotfiles/`，只在需要 Guix 介入时改 `config.org`
- 能用 Home 解决就不用 System

**Don't**：

- 不要手动编辑 `tmp/config.scm`
- `<<ref>>` 是 Org Noweb 语法，非 Scheme
  </critical>

## 块级精准编辑

修改 `config.org` 中单个 `#+NAME:` 块时，用 block-\* 任务避免读 2000 行文件：

```bash
# 提取块 body（首两行: lang= 和 noweb/plain 标记，第 3 行起是实际内容）
FILE=$(blue block-show dotfile-services 2>/dev/null | tail -1)
tail -n +3 "$FILE" > /tmp/new-body.scm   # 编辑 body
blue block-replace dotfile-services /tmp/new-body.scm  # 替换 + 验证
```

**要点**：

- 括号验证仅对 scheme 块触发（fish/bash/js 跳过）
- body 可能含 `<<ref>>` 占位，需自行追踪被引用块
- 验证失败时手动 `git checkout source/config.org` 恢复
- 适合低耦合的小块；改大块（如 `emacs-services`）仍建议读整段

## 修改约束

- `config.org` 是唯一 Org 源，**不要**新建第二个
- 头部代码块（全局变量、文件系统、内核）同时影响 system 和 home
- 启动时序敏感的服务集中在 `filesystem-services` 块
- 新增 dotfile 子目录后必须更新 `dotfile-services` 的 `packages` 列表
