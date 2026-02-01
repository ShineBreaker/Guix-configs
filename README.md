<!--
SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>

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

```bash
# 这里会把系统和用户的配置都给配置好
sudo guix system reconfigure config.scm
```

### 利用just

安装完系统之后就可以直接在仓库的根目录中使用just来便捷的对系统进行操作了

```bash
❯ just --list
Available recipes:
  home      # 应用用户配置
  home-v    # 应用用户配置 (详细显示日志)
  rebuild   # 应用全局配置
  rebuild-v # 应用全局配置 (详细显示日志)
  system    # 应用系统配置
  system-v  # 应用系统配置 (详细显示日志)
  upgrade   # 更新lock file
```

### 核心配置
- **内核**: Linux xanmod (in nonguix channel.)
- **时区**: Asia/Shanghai
- **语言环境**: zh_CN.utf8
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

详见`./configs/imformation.scm`, 那边利用了Scheme语法来做到绑定subvol, 
并将`/home`分区中需要持久化保存的目录放置在
`/data  (subvol=DATA/Share)`
中,并利用`bind-mount`来做目录绑定.

### 内核优化

配置了多项内核参数以提升系统性能：

- 启用 zswap 压缩交换
- 网络优化：BBR 拥塞控制、TCP 快速打开
- 虚拟内存优化：减少缓存压力、降低页锁不公平性
- 禁用 NUMA 平衡、启用调度自动分组

### 字体配置

- **无衬线字体**: Sarasa Gothic SC (更纱黑体 SC) 
- **等宽字体**: Maple Mono NF CN (放在了我自己的channel里面)
- **Emoji**: Noto Color Emoji

## 文件结构

```
.
├── config.scm                             # 系统级主配置文件
├── configs/                               # 配置模块目录
│   ├── channel.scm                        # Guix 频道定义
│   ├── channel.lock                       # Guix 频道锁文件
│   ├── information.scm                    # 全局变量定义
│   ├── system-config.scm                  # 系统配置聚合文件
│   ├── home-config.scm                    # Home 环境配置聚合文件
│   ├── files/                             # 系统配置文件目录
│   │   ├── config.fish                    # Fish Shell 配置
│   │   ├── nftables.conf                  # 防火墙规则配置
│   │   └── postgresql.conf                # PostgreSQL 数据库配置
│   ├── system/                            # 系统级配置模块
│   │   ├── bootloader.scm                 # GRUB/UKI 引导加载器配置
│   │   ├── filesystems.scm                # 文件系统、Btrfs 子卷、LUKS 加密配置
│   │   ├── kernel.scm                     # 内核版本、固件、内核参数配置
│   │   ├── modules.scm                    # Guix 模块导入
│   │   ├── packages.scm                   # 系统级软件包列表
│   │   ├── services.scm                   # 系统级服务配置
│   │   └── users.scm                      # 时区、语言、主机名、用户账户配置
│   └── home/                              # 用户环境配置模块
│       ├── modules.scm                    # Home 模块导入
│       ├── package.scm                    # 用户级软件包列表
│       └── services/                      # Home 服务配置
│           ├── desktop.scm                # 桌面环境服务 (Niri, Waybar, Fcitx5 等)
│           ├── dotfile.scm                # dotfiles 管理配置
│           ├── environment-variables.scm  # 环境变量配置
│           ├── fish.scm                   # Fish Shell 配置
│           └── font.scm                   # 字体配置
├── dotfiles/                              # 用户配置文件目录
│   .
│   .
│   .
│   
├── justfile                               # Just 任务运行器配置
├── LICENSE                                # 项目许可证
└── README.md                              # 项目说明文档
```

### 配置文件说明

采用模块化设计，将配置拆分为多个文件以提高可维护性。

**主配置文件**：

- `config.scm` - 系统级主配置文件，加载并组合系统配置模块

**全局配置** (`configs/` 根目录)：

- `channel.scm` - 定义 Guix 软件包频道（包含 nonguix 等第三方频道）
- `channel.lock` - Guix 频道版本锁定文件
- `information.scm` - 定义系统基本信息，包括 tmpfs 需要持久化的目录相关配置
- `system-config.scm` - 系统配置聚合文件，整合所有系统级模块
- `home-config.scm` - Home 环境配置聚合文件，整合所有用户环境模块

**系统配置文件** (`configs/files/` 目录)：

- `config.fish` - Fish Shell 全局配置
- `nftables.conf` - nftables 防火墙规则
- `postgresql.conf` - PostgreSQL 数据库服务配置

**系统配置模块** (`configs/system/` 目录)：

- `modules.scm` - 导入系统配置所需的 Guix 模块
- `bootloader.scm` - 配置引导加载器 (GRUB/UKI)
- `filesystems.scm` - 配置文件系统挂载点和 Btrfs 子卷，以及配置 LUKS 磁盘加密和映射设备
- `kernel.scm` - 配置内核版本、微码、固件和内核参数
- `packages.scm` - 定义系统要安装的软件包列表
- `services.scm` - 配置系统级服务（网络、音频、显示管理等）
- `users.scm` - 配置系统时区、语言环境、主机名和用户账户

**Home 配置模块** (`configs/home/` 目录)：

- `modules.scm` - 导入 Home 配置所需的 Guix 模块
- `package.scm` - 定义用户环境的软件包列表
- `services/desktop.scm` - 配置桌面环境所需要的服务（窗口管理器、状态栏、输入法等）
- `services/dotfile.scm` - 配置其他软件所使用的配置文件
- `services/environment-variables.scm` - 配置用户环境变量
- `services/fish.scm` - 配置 Fish Shell 交互式环境
- `services/font.scm` - 配置用户字体设置



### 特别感谢

Grok、ChatGPT、Gemini：帮我解决问题

GLM：帮忙拆分了一下我的配置文件

[GNU/Guix China群聊](https://t.me/guixcn)：帮助解决了进入系统的大问题, 才终于让我用上了Guix

---

**日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。**--《日常》
