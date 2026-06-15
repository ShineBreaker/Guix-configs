# Guix-configs — 仓库导引

本文件为在本仓库工作的 AI 助手提供统一指引。`CLAUDE.md` 是本文件的符号链接。

## 概述

以 Guix 为核心的个人系统配置仓库，单一 `source/config.org` 同时声明 `operating-system` 和 `home-environment`，通过 `maak` 构建并部署。

```
.
├── source/                 # Guix System / Home 的 Scheme + Org 源（唯一权威）
│   ├── config.org          # 唯一的 Org 配置源（system + home 全 Noweb 拼合）
│   ├── channel.scm         # 频道定义
│   ├── channel.lock        # 频道版本锁定（由 maak update 自动更新）
│   ├── information.scm     # 全局变量（username、%data-dirs、%btrfs-subvolumes）
│   ├── files/              # 静态模板（nftables.conf、rounded.qss、zed.json、skel/）
│   └── nix/                # Nix home-manager 备份分支（独立使用，与 Guix 不互通）
├── dotfiles/
│   ├── enable/             # 当前启用的配置（统一由 Guix Home stow 部署）
│   └── disable/            # 已弃用的旧配置（保留参考）
├── tmp/                    # maak 生成的中间产物（自动生成，不要手动编辑）
├── tools/                  # 辅助脚本
└── maak.scm                # 任务运行器定义（基于 maak-mono Scheme DSL）
```

## 构建管线

```
source/config.org
        │
        ▼  maak rebuild → Emacs org-babel-tangle（Noweb 拼合）
tmp/config.scm
        │
        ▼  guix time-machine --channels=source/channel.lock system reconfigure
单一 reconfigure：同时应用 operating-system 与 guix-home-service（含 home-environment）
```

- Org 文件使用 Noweb `<<ref>>` 语法拼合代码块为完整 `.scm`
- 所有 `guix` 命令通过 `guix time-machine --channels=source/channel.lock` 锁定频道版本
- 单一 `maak rebuild` 完成：tangle → 括号检查 → reconfigure → `guix locate --update`
- DRY_RUN 时仅 tangle + 括号检查 + `dry-run`，不实际写入系统

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENTS.md`（`source/`、`dotfiles/enable/<app>/`、emacs 子模块内）
2. 若 README / 文档与实际文件不一致，以仓库实际结构和源码为准
3. **禁止直接修改 `~/.config/`、`~/.local/` 等已部署位置。** 所有配置必须改源文件后通过 `maak home` 生效

## 任务路由表

| 任务类型           | 优先读取位置                                    | 子目录指引                                 |
| ------------------ | ----------------------------------------------- | ------------------------------------------ |
| System + Home 配置 | `source/config.org` 头部的 Agent 专区           | `source/AGENTS.md`                         |
| **Emacs 配置**     | `dotfiles/enable/emacs/.config/emacs/AGENTS.md` | 子模块 `codeberg.org/BrokenShine/.emacs.d` |
| 全局变量           | `source/information.scm`                        | —                                          |
| 频道定义           | `source/channel.scm`                            | `source/channel.lock` 锁定版本             |
| 静态模板           | `source/files/`                                 | `source/AGENTS.md` 中 files/ 模板系统一节  |
| 各类 dotfiles      | `dotfiles/enable/<app>/`                        | 各子目录 AGENTS.md                         |

<critical>
**路由硬约束**：
1. 遇到 Home / System 配置任务时，先读 `source/config.org` 头部的 *Agent 指引* 两节（系统段与用户段）+ `source/AGENTS.md`
2. 修改应用配置时优先改 `dotfiles/enable/<app>/` 内文件，再 `maak rebuild`
3. **Emacs 修改**：先读 `dotfiles/enable/emacs/.config/emacs/AGENTS.md`，新包必须同步 `source/config.org` 的 home-packages
4. **Agent 配置（Pi/Crush）**：先读 `dotfiles/enable/agents/AGENTS.md`（部署模型、settings.json 归属表）
5. **绝对不要**直接编辑 `tmp/` 下任何产物（重新 tangle 会被覆盖）
6. 优先使用 `maak --list` 内可以使用的相关命令
</critical>

## dotfiles 部署模型

所有 `dotfiles/enable/<app>/` 子目录统一通过 Guix Home 的 `home-dotfiles-service-type` 部署，定义在 `source/config.org` 的 `dotfile-services` 代码块：

```scheme
(service home-dotfiles-service-type
  (home-dotfiles-configuration
   (directories '("../dotfiles/enable"))
   (layout 'stow)                         ; Stow 软链接语义
   (packages '("agents" "desktop" "desktop-suite"
               "emacs" "system" "terminal" "utilities"))
   (excluded '("\\.agents/workfile($|/.*)" ...))))
```

- 实际机制：构建时把目录软链接到 `$HOME`，运行期视同只读（用户不要手动 `~/.config/...` 改东西）
- **不存在顶层 `immutable/` + `mutable/` 拆分**；旧结构已并入 `enable/<app>/`
- 不在 `excluded` 列表内的新增文件会在下次 `maak rebuild` 后自动出现在 `~`
- `disable/` 内目录不再部署，仅保留参考

子模块位于 `enable/` 下，路径如下，**不要直接编辑子模块内容**：

| 路径                                                                | 上游                                 |
| ------------------------------------------------------------------- | ------------------------------------ |
| `dotfiles/enable/emacs/.config/emacs`                               | `codeberg.org/BrokenShine/.emacs.d`  |
| `dotfiles/enable/utilities/.local/share/fcitx5/rime`                | `github.com/iDvel/rime-ice`          |
| `dotfiles/enable/agents/.config/agents/skillsets/agent-skills`      | `github.com/addyosmani/agent-skills` |
| `dotfiles/enable/agents/.config/agents/skillsets/emacs-skills`      | `github.com/xenodium/emacs-skills`   |
| `dotfiles/enable/agents/.config/agents/skillsets/mattpocock-skills` | `github.com/mattpocock/skills`       |
| `dotfiles/enable/agents/.config/agents/skillsets/pi-skills`         | `github.com/badlogic/pi-skills`      |

## 频道架构

| 频道        | 分支   | 职责         | URL（以 `source/channel.scm` 为准）         |
| ----------- | ------ | ------------ | ------------------------------------------- |
| `guix`      | master | 官方包集合   | `https://git.guix.gnu.org/guix.git`         |
| `jeans`     | main   | 个人自定义包 | `https://github.com/ShineBreaker/jeans.git` |
| `nonguix`   | master | 非自由软件   | `https://gitlab.com/nonguix/nonguix`        |
| `rosenthal` | trunk  | WM 增强组件  | `https://codeberg.org/hako/rosenthal.git`   |

- 频道版本锁定在 `source/channel.lock`，由 `maak update` 自动生成并 `git commit -S`
- **不要手动编辑 `channel.lock`**（重生成会覆盖你的改动）
- `source/information.scm` 通过 `(include "./channel.lock")` 加载锁定版本

## 文件系统架构

- **根目录**：tmpfs（重启后清空）
- **持久化**：Btrfs 子卷挂载到 `/var/lib`、`/gnu`、`/var/cache`、`/boot` 等
- **用户数据**：`/data` 分区通过 bind-mount 映射到 `~`（具体映射见 `%btrfs-subvolumes`）
- **`/home`**：tmpfs，启动时由 `filesystem-services` 从 `DATA/Home/Guix` 子卷重建并按 `%data-dirs` bind-mount

> 任何持久化目录必须同时在 `source/information.scm` 的 `%data-dirs` 和 `%btrfs-subvolumes` 中登记。

## 全局变量速查（`source/information.scm`）

被 `source/config.org` 头部通过 `(load "../source/information.scm")` 加载。

| 变量                 | 类型   | 说明                                                            |
| -------------------- | ------ | --------------------------------------------------------------- |
| `username`           | string | 主用户名（`"brokenshine"`）                                     |
| `fixed-machine-id`   | string | 基于 `username` 的 MD5（保证跨机器一致）                        |
| `%data-dirs`         | list   | 需要 bind-mount 持久化的用户子目录（XDG + dotfile 状态）        |
| `%btrfs-subvol-data` | string | 数据分区子卷路径（`"DATA/Share"`）                              |
| `%btrfs-subvolumes`  | alist  | Btrfs 子卷 → 挂载点映射                                         |
| `guix-channels`      | list   | 从 `channel.lock` 加载的频道列表（`(include "./channel.lock")`) |

### 配置验证（DRY_RUN）

修改 `source/config.org` 后，**务必**先 dry-run 验证再实际应用：

```bash
MAAK_DRY_RUN=1 maak rebuild   # 仅构建一次，不写入系统
maak check                    # 最快：仅括号平衡检查
```

## Org Noweb 机制

`source/config.org` 使用 Org Mode 的 Noweb 功能拼合代码块：

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他代码块中引用（**不是** Scheme 原生语法，是 Org Mode 功能）
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标

## 风险点

- 不要手动编辑 `tmp/` 下任何产物
- 不要绕过 `maak` 直接调 `guix system reconfigure`（频道不会被锁）
- 修改 `dotfiles/` 内容后必须 `maak home`，否则不会生效
- **禁止 AI agent 自行运行 `maak rebuild` / `guix system reconfigure`**：这些命令会要求使用 `sudo` 提权，导致CLI卡死。
  修改 dotfiles 或 source 后，只能够运行 `maak home` ，该指令会在下次重启前暂时应用，待确认功能正常后再提醒用户运行 `maak rebuild` 固化配置即可。
- **pi 扩展必须是单文件 `index.ts`**：Guix Home stow 逐文件软链接到 `/gnu/store/`，导致 jiti 的相对路径 `import` 断裂。
