<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

```
▗▄▄▖  ▄▄▄ ▄▄▄  █  ▄ ▗▞▀▚▖▄▄▄▄   ▗▄▄▖▐▌   ▄ ▄▄▄▄  ▗▞▀▚▖  ▄   ▄▄▄
▐▌ ▐▌█   █   █ █▄▀  ▐▛▀▀▘█   █ ▐▌   ▐▌   ▄ █   █ ▐▛▀▀▘     ▀▄▄
▐▛▀▚▖█   ▀▄▄▄▀ █ ▀▄ ▝▚▄▄▖█   █  ▝▀▚▖▐▛▀▚▖█ █   █ ▝▚▄▄▖     ▄▄▄▀
▐▙▄▞▘          █  █            ▗▄▄▞▘▐▌ ▐▌█

                                           ▗▄▄▖█  ▐▌▄ ▄   ▄
                                          ▐▌   ▀▄▄▞▘▄  ▀▄▀
                                          ▐▌▝▜▌     █ ▄▀ ▀▄
                                          ▝▚▄▞▘     █

                                          ▗▄▄▖▄▄▄  ▄▄▄▄  ▗▞▀▀▘ ▄   █  ▐▌ ▄▄▄ ▗▞▀▜▌   ■  ▄  ▄▄▄  ▄▄▄▄
                                         ▐▌  █   █ █   █ ▐▌    ▄   ▀▄▄▞▘█    ▝▚▄▟▌▗▄▟▙▄▖▄ █   █ █   █
                                         ▐▌  ▀▄▄▄▀ █   █ ▐▛▀▘  █        █           ▐▌  █ ▀▄▄▄▀ █   █
                                         ▝▚▄▄▖           ▐▌    █ ▗▄▖                ▐▌  █
                                                                ▐▌ ▐▌               ▐▌
                                                                 ▝▀▜▌
                                                                ▐▙▄▞▘
```

## 使用方法

### 安装系统

直接在仓库根目录使用 `maak` 即可便捷地对系统进行操作：

```bash
guix shell maak -- maak init
```

### 安装系统之后

在仓库中运行 `maak` 查看所有可用指令：

```bash
maak --list
```

常用命令：

```bash
maak system
maak home
maak rebuild
```

### 系统预览

![日常使用](screenshots/daily.png)
![终端](screenshots/terminal.png)
![Emacs](screenshots/emacs.png)

### 核心配置

- **内核**: Linux xanmod (in nonguix channel.)
- **时区**: Asia / Shanghai
- **语言环境**: zh_CN. utf8
- **Shell**: Fish

### 桌面环境

- **显示服务器**: Wayland
- **窗口合成器**: Niri
- **显示管理器**: Greetd (with tuigreet)
- **锁屏器**: gtklock
- **终端**: Foot
- **菜单启动器**: Fuzzel
- **状态栏**: Waybar
- **输入法**: Fcitx5 + Rime
- **文件管理器**: Thunar

### 文件系统

- **架构**: 混合架构 (tmpfs + Btrfs)
- **加密**: LUKS 磁盘加密
- **根目录**: tmpfs (临时文件系统, 重启后清空)
- **持久化**: Btrfs 子卷 (重启后保留数据)

**Btrfs 持久化子卷**

详见 `./configs/information.scm`，

利用 Scheme 语法定义 subvol，

并将 `/home` 分区中需要持久化保存的目录放置在

`/data (subvol=DATA/Share)`

中，再利用 `bind-mount` 做目录绑定。

### 内核优化

配置了多项内核参数以提升系统性能:

- 启用 zswap 压缩交换
- 网络优化: BBR 拥塞控制, TCP 快速打开
- 虚拟内存优化: 减少缓存压力, 降低页锁不公平性
- 禁用 NUMA 平衡, 启用调度自动分组

### 字体配置

- **无衬线字体**: Sarasa Gothic SC (更纱黑体 SC)
- **等宽字体**: Maple Mono NF CN (放在了我自己的 channel 里面)
- **Emoji**: Noto Color Emoji

## 文件结构

```text
.
├── AGENT.md                 # 仓库级 AI 工作指引
├── README.md                # 项目说明文档
├── maak.scm                 # maak 的配置文件
├── docs/                    # 文档目录
│   └── terminal-ide.md      # 终端 IDE 功能说明
├── source/                  # 配置源码目录
│   ├── channel.scm          # Guix 频道定义
│   ├── channel.lock         # Guix 频道锁文件
│   ├── information.scm      # 全局变量定义
│   ├── files/               # 静态配置模板与资源文件
│   └── configs/             # Guix 配置文档
│       ├── home-config.md   # Home 配置说明
│       └── system-config.md # 系统配置说明
├── dotfiles/                # 用户配置文件目录
│   └── .config/             # 用户级配置
│       └── emacs/           # Emacs 配置子树
├── screenshots/             # 预览截图
├── setup/                   # 安装辅助脚本子模块
└── LICENSE                  # 项目许可证
```

### 配置文件说明

采用模块化设计，将配置拆分为多个文件以提高可维护性。

**任务入口**：

- `maak.scm` - `maak` 的配置文件
  `maak` 是一个类似于 `make` 的代码运行器，但是使用Guile作为默认语言

**源码目录**（`source/`）：

- `channel.scm` - 定义 Guix 软件包频道（包含 nonguix 等第三方频道）
- `channel.lock` - Guix 频道版本锁定文件
- `information.scm` - 定义系统基本信息，包括用户名、channel、Btrfs 子卷和持久化目录
- `files/` - 静态配置模板与资源文件（nftables.conf、mihomo.yaml、niri.kdl 等）
- `configs/` - 配置说明文档
  - `home-config.md` - Home 环境配置详细说明
  - `system-config.md` - 系统配置详细说明

**说明**：

- 实际的 Scheme 配置模块通过 `maak` 从 `source/` 生成到 `tmp/` 目录后执行
- 系统配置和用户配置分离，便于独立迭代

**Dotfiles**（`dotfiles/` 目录）：

- 存放实际分发到用户家目录的配置文件
- `dotfiles/.config/emacs/` 是独立维护的 Emacs 配置子树

**子模块**：

- `setup/` - Linux 安装辅助脚本
- `dotfiles/.local/share/fcitx5/rime` - Rime 词库子模块

**文档**（`docs/` 目录）：

- `terminal-ide.md` - 终端 IDE（tmux + helix + broot）功能说明

### 特别感谢

Grok, ChatGPT, Gemini, Kimi, Claude, GLM, Qwen: 帮我解决问题

- GLM: 帮忙拆分了一下我的配置文件, 并起草了 configen 的初版
- Grok: 负责查询部分功能的用法
- Kimi, Qwen, Gemini: 帮我起草了 Emacs 的配置文件的基础功能
- ChatGPT: 替我完善了初版 Emacs 配置文件, 并帮助实现了多个功能
- Claude: 帮我完善并重新梳理了 Emacs 配置文件

[GNU/Guix China群聊](https://t.me/guixcn): 帮助解决了进入系统的大问题, 才终于让我用上了 Guix

---

**日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。**--《日常》
