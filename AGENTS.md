本文件为在本仓库中工作的 AI 助手提供统一指引。`CLAUDE.md` 是本文件的符号链接。

## 概述

以 Guix 为核心的个人系统配置仓库：

- `source/`：Guix System / Guix Home 的 Scheme 源配置和 org 文档
- `dotfiles/`：通过 Home 服务分发到用户目录的配置文件集合
- `tmp/`：`maak` 生成的完整配置（临时目录，不应手动编辑）
- `tools/`：辅助工具

## 构建管线

```
source/config.org
        │
        ▼  maak apply → Emacs org-babel-tangle（Noweb 拼合）
tmp/config.scm
        │
        ▼  guix time-machine --channels=source/channel.lock system reconfigure
系统 + 用户环境（同一 .scm 同时声明 operating-system 和 home-environment）
```

- Org 文件使用 Noweb `<<ref>>` 语法拼合代码块为完整 .scm
- `maak` 基于 Scheme 定义在 `maak.scm` 中，所有 guix 命令通过 `guix time-machine --channels=source/channel.lock` 锁定频道版本

## 工作优先级

1. 先看当前目录是否存在更近的 `AGENTS.md`（如 `source/AGENTS.md`）
2. 若修改 `dotfiles/enable/emacs/.config/emacs/`，遵循其局部 `AGENTS.md`
3. 若 README 与实际文件不一致，以实际仓库结构和源码为准

## 文件路由表

| 任务类型          | 优先读取位置                                | 子目录指引                |
| ----------------- | ------------------------------------------- | ------------------------- |
| 系统 + 用户配置   | `source/config.org` 头部的 Agent 专区       | `source/AGENTS.md`        |
| **Emacs 配置**    | `dotfiles/enable/emacs/.config/emacs/AGENTS.md` | 含知识库体系，详见下方   |
| **Pi Agent 配置** | `dotfiles/enable/agents/.config/pi/`        | settings.json + agents/   |
| 全局变量          | `source/information.scm`                    | —                         |
| 频道定义          | `source/channel.scm`                        | —                         |
| 静态模板          | `source/files/`                             | `source/AGENTS.md`        |
| dotfiles          | `dotfiles/enable/<app>/`                    | —                         |

<critical>
**路由指令**：
1. 遇到 Home/System 配置任务时，优先读取 `source/config.org` 头部的 Agent 专区 + `source/AGENTS.md`
2. 修改软件配置时，优先修改 `dotfiles/enable/` 内的文件，再提醒用户运行 `maak apply`，**绝对禁止直接修改 home 中的相关文件**
3. **Emacs 配置修改**：先读 `dotfiles/enable/emacs/.config/emacs/AGENTS.md`，新包需同步修改 `source/config.org` 的包清单
4. **Pi Agent 修改**：先读 `dotfiles/enable/agents/.config/pi/` 下的配置，settings.json 是核心配置

## dotfiles 三层结构

```
dotfiles/
dotfiles/
├── enable/      # 当前启用的配置（包含 immutable + mutable 两类）
│   ├── agents/      # AI 助手系统（Pi/Crush/KB skills）
│   ├── desktop/     # 桌面环境（niri WM、autostart、portal）
│   ├── desktop-suite/  # WM 主题套件（darkman、waybar、fuzzel、mako）
│   ├── emacs/       # Emacs 配置（子模块 → codeberg.org/BrokenShine/.emacs.d）
│   ├── system/      # 系统级（containers、pipewire、xdg-dirs）
│   ├── terminal/    # 终端工具链（fish、tmux、foot、btop、starship）
│   └── utilities/   # 开发工具（helix、git、kanata、winapps、rime）
└── disable/    # 已禁用的旧配置（noctalia）

- `enable/<dir>/`：按子目录由 Guix Home（immutable 类）或 GNU Stow（mutable 类）管理
  - immutable 类（agents、desktop、desktop-suite、system、terminal、utilities）通过 Guix Home 的 `home-dotfiles-service-type` 管理
  - mutable 类（emacs、agents 等可热调试项）通过 GNU Stow 链接到 `$HOME`，可直接修改后 `maak apply` 重链
- `disable/`：不再启用的配置文件，保留供参考
- 各子目录详见 `dotfiles/AGENTS.md` 及子目录局部 AGENTS.md

## 频道架构

| 频道      | 分支   | 职责         | URL（以 channel.scm 为准）                  |
| --------- | ------ | ------------ | ------------------------------------------- |
| guix      | master | 官方包集合   | `https://git.guix.gnu.org/guix.git`         |
| jeans     | main   | 个人自定义包 | `https://github.com/ShineBreaker/jeans.git` |
| nonguix   | master | 非自由软件   | `https://gitlab.com/nonguix/nonguix`        |
| rosenthal | trunk  | WM 增强组件  | `https://codeberg.org/hako/rosenthal.git`   |

频道版本锁定在 `source/channel.lock`，由 `maak update` 自动更新并 git commit。**不要手动编辑 channel.lock。**

## 文件系统架构

- **根目录**：tmpfs（重启后清空）
- **持久化**：Btrfs 子卷挂载到 `/var/lib`、`/gnu`、`/var/cache` 等
- **用户数据**：`/data` 分区通过 bind-mount 映射到用户目录
- 子卷映射定义在 `source/information.scm` 的 `%btrfs-subvolumes`
- 用户数据目录列表定义在 `%data-dirs`

## 全局变量速查（information.scm）

| 变量                 | 类型   | 说明                             |
| -------------------- | ------ | -------------------------------- |
| `username`           | string | `"brokenshine"`                  |
| `fixed-machine-id`   | string | 基于 username 的 MD5 生成        |
| `%data-dirs`         | list   | 需要持久化的用户数据目录         |
| `%btrfs-subvol-data` | string | 数据分区子卷路径 `"DATA/Share"`  |
| `%btrfs-subvolumes`  | alist  | 子卷 → 挂载点映射                |
| `guix-channels`      | list   | 从 `channel.lock` 加载的频道列表 |

`information.scm` 被 `source/config.org` 头部通过 `(load "../source/information.scm")` 加载。

## maak 命令

<critical>
优先使用 `maak` 打包的命令。如果已有指令不满足需要且需大量反复使用，写入 `maak.scm`。
</critical>

maak init       # 安装系统到 /mnt（自动提权）
maak check      # 仅括号检查（tangle 后验证 Scheme 语法平衡，不调用 guix）
maak apply      # guix system reconfigure（自动 tangle + 括号检查 + time-machine）
maak rebuild    # apply + guix locate --update（重建文件索引）
maak update     # 更新 channel.lock + git commit -S
maak pull       # guix pull --allow-downgrades --fallback
maak clean      # 删除所有旧 system generations（慎用，默认删除全部旧版本）
maak gc         # clean + guix gc + 清理旧 EFI 文件（⚠ 非 Guix 命令，直接操作 /boot 分区）
maak reuse      # 为所有文件添加 SPDX 版权头

### 配置验证

<critical>
修改 `.org` 配置后，务必先用 dry-run 验证再实际应用。
</critical>

# Dry-run：tangle + 括号检查 + guix build --dry-run（不实际应用）
MAAK_DRY_RUN=1 maak apply

# 单独括号平衡检查（不触发 guix，最轻量）
maak check

## Git 子模块

| 路径                                                                 | 说明                                            |
| -------------------------------------------------------------------- | ----------------------------------------------- |
| `dotfiles/enable/emacs/.config/emacs`                                | Emacs 配置（codeberg.org/BrokenShine/.emacs.d） |
| `dotfiles/enable/utilities/.local/share/fcitx5/rime`                 | Rime 输入法配置（github.com/iDvel/rime-ice）    |
| `dotfiles/enable/agents/.config/agents/skillsets/agent-skills`      | Agent skills 技能集                             |
| `dotfiles/enable/agents/.config/agents/skillsets/emacs-skills`      | Emacs 技能集                                    |
| `dotfiles/enable/agents/.config/agents/skillsets/mattpocock-skills` | Matt Pocock 技能集                              |
| `dotfiles/enable/agents/.config/agents/skillsets/pi-skills`          | Pi Agent 技能集                                 |

不要直接编辑子模块内容。

## Org Noweb 机制

`source/config.org` 使用 Org Mode 的 Noweb 功能：

- `#+NAME: ref` 命名代码块
- `<<ref>>` 在其他代码块中引用（这**不是** Scheme 原生语法，是 Org Mode 功能）
- 最终由 `emacs --batch org-babel-tangle` 展开为完整 .scm 到 `tmp/`

## 风险点

- 不要手动编辑 `tmp/` 目录中的文件
- 优先修改 `source/config.org`（唯一的 org 源文件），不再有 home-config / system-config 之分
- **禁止直接修改 `~/.config/`、`~/.local/` 等安装位置的文件。** 所有配置必须修改 `dotfiles/` 中的源文件，再通过 `maak apply` 生效
- `CLAUDE.md` 是 `AGENTS.md` 的符号链接，修改其中一个即同步修改另一个
- README 中的频道 URL 等信息可能滞后于 `channel.scm`，以 `.scm` 源码为准
