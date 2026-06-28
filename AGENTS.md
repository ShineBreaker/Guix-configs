# Guix-configs — 仓库导引

本文件为在本仓库工作的 AI 助手提供统一指引。`CLAUDE.md` 是本文件的符号链接。

## 概述

以 Guix 为核心的个人系统配置仓库，单一 `source/config.org` 同时声明 `operating-system` 和 `home-environment`，通过 `blue` 构建并部署。

```
.
├── source/                 # Guix System / Home 的 Scheme + Org 源（唯一权威）
│   ├── config.org          # 唯一的 Org 配置源（system + home 全 Noweb 拼合）
│   ├── channel.scm         # 频道定义
│   ├── channel.lock        # 频道版本锁定（由 blue update 自动更新）
│   ├── information.scm     # 全局变量（username、%data-dirs、%btrfs-subvolumes）
│   ├── files/              # 静态模板（nftables.conf、rounded.qss、zed.json、skel/）
│   └── nix/                # Nix home-manager 备份分支（独立使用，与 Guix 不互通）
├── dotfiles/
│   ├── enable/             # 当前启用的配置（统一由 Guix Home stow 部署）
│   └── disable/            # 已弃用的旧配置（保留参考）
├── tmp/                    # blue 生成的中间产物（自动生成，不要手动编辑）
├── tools/                  # 辅助脚本
└── blueprint.scm           # 任务运行器定义（基于 blue-mono Scheme DSL）
```

## 构建管线

```
source/config.org
        │
        ▼  blue rebuild → Emacs org-babel-tangle（Noweb 拼合）
tmp/config.scm
        │
        ▼  guix time-machine --channels=source/channel.lock system reconfigure
单一 reconfigure：同时应用 operating-system 与 guix-home-service（含 home-environment）
```

- Org 文件使用 Noweb `<<ref>>` 语法拼合代码块为完整 `.scm`
- 所有 `guix` 命令通过 `guix time-machine --channels=source/channel.lock` 锁定频道版本
- 单一 `blue rebuild` 完成：tangle → 括号检查 → reconfigure → `guix locate --update`
- `blue --dry-run` 时：tangle + 括号检查仍真跑（构造验证所需产物），其余命令（reconfigure/clean/gc/stow 等）短路打印不执行

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENTS.md`（`source/`、`dotfiles/enable/<app>/`、emacs 子模块内）
2. 若 README / 文档与实际文件不一致，以仓库实际结构和源码为准
3. **禁止直接修改 `~/.config/`、`~/.local/` 等已部署位置。** 所有配置必须改源文件后通过 `blue home` 生效
4. **新机装机引导**：`tools/bootstrap.sh` 是入口；先读 `source/manifest.scm` 了解依赖图。

## 任务路由表

| 任务类型             | 优先读取位置                                 | 子目录指引                                |
| -------------------- | -------------------------------------------- | ----------------------------------------- |
| System + Home 配置   | `source/config.org` 头部的 Agent 专区        | `source/AGENTS.md`                        |
| 全局变量             | `source/information.scm`                     | —                                         |
| 频道定义             | `source/channel.scm`                         | `source/channel.lock` 锁定版本            |
| 静态模板             | `source/files/`                              | `source/AGENTS.md` 中 files/ 模板系统一节 |
| 各类 dotfiles        | `dotfiles/enable/<app>/`                     | 各子目录 AGENTS.md                        |
| 新机装机（官方 ISO） | `source/manifest.scm` + `tools/bootstrap.sh` | —                                         |

<critical>
**路由硬约束**：
1. 遇到 Home / System 配置任务时，先读 `source/config.org` 头部的 *Agent 指引* 两节（系统段与用户段）+ `source/AGENTS.md`
2. 修改应用配置时优先改 `dotfiles/enable/<app>/` 内文件，再 `blue home`
3. **Emacs 修改**：先读 `stow/emacs/.config/emacs/AGENTS.md`，新包必须同步 `source/config.org` 的 home-packages
4. **Agent 配置（Pi/Crush）**：先读 `dotfiles/enable/agents/AGENTS.md`（部署模型、settings.json 归属表）
5. **绝对不要**直接编辑 `tmp/` 下任何产物（重新 tangle 会被覆盖）
6. 优先使用 `blue --list` 内可以使用的相关命令
</critical>

## 引导（新机安装）

官方 Guix ISO 上只有 `blue` 需要预先引导（emacs 由 `guix time-machine shell emacs-minimal` 自动供给）。

两个支撑文件：

- `source/manifest.scm`：声明引导依赖（目前仅 `blue`）
- `tools/bootstrap.sh`：锁定频道 + 提供可执行 `blue`

```bash
git clone <url> && cd Guix-configs
./tools/bootstrap.sh   # 进入带 blue 的临时 shell（首次较慢）
# 分区/格式化/挂载 /mnt 后：
blue init
```

`bootstrap.sh` **不会**自动分区或跑 `blue init`。自制 ISO 可直接引用 `source/manifest.scm`。

## dotfiles 部署模型

所有 `dotfiles/enable/<app>/` 子目录统一通过 Guix Home 的 `home-dotfiles-service-type` 部署，定义在 `source/config.org` 的 `dotfile-services` 代码块：

```scheme
(service home-dotfiles-service-type
  (home-dotfiles-configuration
   (directories '("../dotfiles/enable"))
   (layout 'stow)                         ; Stow 软链接语义
   (packages '("agents" "desktop"
                 "noctalia-suite" "system" "terminal" "utilities"))
   (excluded '("\\.agents/workfile($|/.*)" ...))))
```

- 实际机制：构建时把文件 _复制到 `/gnu/store/<hash>-home-dotfiles-...`_（只读副本），再从 store 软链接到 `$HOME`。
  **`~/.config/<app>/...` 指向 store 副本，不是仓库源** —— 改源后 store 副本不变，必须 `blue home` 重建软链接才生效
- 不在 `excluded` 列表内的新增文件会在下次 `blue home` 后自动出现在 `~`
- `disable/` 内目录不再部署，仅保留参考

子模块位于 `enable/` 下，路径如下，**不要直接编辑子模块内容**：

| 路径                                                 | 上游                                |
| ---------------------------------------------------- | ----------------------------------- |
| `stow/emacs/.config/emacs`                           | `codeberg.org/BrokenShine/.emacs.d` |
| `dotfiles/enable/utilities/.local/share/fcitx5/rime` | `github.com/iDvel/rime-ice`         |

## stow/ — GNU Stow 直链部署

与 `dotfiles/enable/`（Guix Home stow）互补：`stow/` 用 GNU Stow 直接建软链接到仓库源，**改源即生效**，无需 `blue home`。适合频繁手改且需要 git 备份的配置（emacs、pi、hermes）。

```bash
blue stow hermes                 # 部署（建软链接）
blue stow --restow hermes        # 强制重建
blue stow --delete hermes        # 删除软链接
blue stow-all --restow           # 重建所有包
```

详见 `stow/AGENTS.md`。

## 目录结构图自动维护

> **实现位置**：`blueprint.scm` 内的 `structor` 任务；7 个 `AGENTS.md` 里的 `<!-- structor:begin -->...<!-- /structor -->` 标记对。

仓库内所有 `AGENTS.md` 的"## 目录结构"章节用标记圈起，由 `blue structor` 自动重写。

**使用约定**：

- **不要手改**标记之间的内容——会被下次跑 `blue structor` 覆盖
- 新增/移动文件后跑 `blue structor` 刷新所有结构图
- 单文件调试：`ORG_STRUCTOR_TARGET=source/AGENTS.md blue structor`
- 预览不写文件：`ORG_STRUCTOR_DRY=1 blue structor`
- 标记格式独立于运行器（不带 `blue:` 前缀），其他仓库用 justfile/Makefile 包装时复用同一约定
- 跳过规则与 `dotfile-services` 的 `excluded` 列表对齐（`.git` / `.github` / `AGENTS.md` 自身等）
- 新增 dotfile 子目录后想把它的 `AGENTS.md` 也自动维护：把路径加到 `blueprint.scm` 的 `%structor-targets`

## 频道架构

| 频道        | 分支   | 职责         | URL（以 `source/channel.scm` 为准）         |
| ----------- | ------ | ------------ | ------------------------------------------- |
| `guix`      | master | 官方包集合   | `https://git.guix.gnu.org/guix.git`         |
| `jeans`     | main   | 个人自定义包 | `https://github.com/ShineBreaker/jeans.git` |
| `nonguix`   | master | 非自由软件   | `https://gitlab.com/nonguix/nonguix`        |
| `rosenthal` | trunk  | WM 增强组件  | `https://codeberg.org/hako/rosenthal.git`   |

- 频道版本锁定在 `source/channel.lock`，由 `blue update` 自动生成并 `git commit -S`
- **不要手动编辑 `channel.lock`**（重生成会覆盖你的改动）
- `source/information.scm` 通过 `(include "./channel.lock")` 加载锁定版本

## 文件系统架构

- **根目录**：tmpfs（重启清空）
- **持久化**：Btrfs 子卷挂载到 `/var/lib`、`/gnu`、`/boot` 等
- **用户数据**：`/data` 分区 bind-mount 到 `~`

> 持久化目录必须同时在 `%data-dirs` 和 `%btrfs-subvolumes` 中登记。

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

修改 `source/config.org` 后先 dry-run：

```bash
blue --dry-run rebuild        # tangle + 括号检查 + guix build --dry-run，不写入系统
blue check                    # 最快：仅括号平衡检查
```

`--dry-run` 对**所有** `%run` 子进程统一生效（reconfigure/clean/gc/stow/nix 等短路打印）。tangle 与括号检查仍真跑（`#:real?`）以保留验证能力。

## Org Noweb 机制

`source/config.org` 使用 Org Mode 的 Noweb 功能拼合代码块：

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他代码块中引用（**不是** Scheme 原生语法，是 Org Mode 功能）
- `#+begin_src scheme :tangle ../tmp/config.scm :noweb yes` 标记 tangle 目标

## 风险点

> **⚠ 改源 ≠ 生效**：`~/.config/<app>/...` 指向 `/gnu/store` 只读副本，**不是仓库源**。改 dotfiles 后 `md5sum <源>` vs `md5sum ~/.config/<app>/<同路径>` 确认 store hash 已变。

**验证流程**：

1. 改 dotfiles 源
2. `blue home`
3. grep 部署位置确认同步 → restart service + 验证行为

- 不要手动编辑 `tmp/` 下任何产物
- 不要绕过 `blue` 直接调 `guix system reconfigure`（频道不会被锁）
- **禁止 AI agent 自行运行 `blue rebuild` / `guix system reconfigure`**（需 sudo 提权，卡死 CLI）。只许 `blue home` 调试，确认正常后提醒用户手动 `blue rebuild` 固化。
