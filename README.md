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

- **文件系统类型**: Btrfs
- **加密**: LUKS 磁盘加密
- **子卷配置**:
  - `/` - SYSTEM/Guix/@
  - `/home` - DATA/Home/Guix
  - `/data` - DATA/Share
  - `/var/lib/flatpak` - DATA/Flatpak

### 内核优化

配置了多项内核参数以提升系统性能：

- 启用 zswap 压缩交换
- 网络优化：BBR 拥塞控制、TCP 快速打开
- 虚拟内存优化：减少缓存压力、降低页锁不公平性
- 禁用 NUMA 平衡、启用调度自动分组

### 字体配置

- **无衬线字体**: Sarasa Gothic SC（更纱黑体 SC）
- **等宽字体**: Maple Mono NF CN (放在了我自己的channel里面)
- **Emoji**: Noto Color Emoji

## 文件结构

```
.
├── config.scm                             # 系统级主配置文件
├── home-config.scm                        # Home 环境配置文件
├── configs/                               # 配置模块目录
│   ├── channel.scm                        # Guix 频道配置
│   ├── information.scm                    # 系统信息定义
│   ├── system/                            # 系统级配置模块
│   │   ├── modules.scm                    # 系统模块导入
│   │   ├── bootloader.scm                 # 引导加载器配置
│   │   ├── filesystems.scm                # 文件系统配置
│   │   ├── kernel.scm                     # 内核和固件配置
│   │   ├── luks.scm                       # LUKS 加密配置
│   │   ├── packages.scm                   # 系统软件包配置
│   │   ├── services.scm                   # 系统服务配置
│   │   └── users.scm                      # 用户账户配置
│   └── home/                              # Home 级配置模块
│       ├── modules.scm                    # Home 模块导入
│       ├── package.scm                    # Home 软件包配置
│       └── services/                      # Home 服务配置
│           ├── desktop.scm                # 桌面环境配置
│           ├── dotfile.scm                # 配置文件相关配置
│           ├── environment-variables.scm  # 环境变量配置
│           └── font.scm                   # 字体配置
├── dotfiles/                              # 用户配置文件
│   └── .gtkrc-2.0
.
.
.
```

### 配置文件说明

我对每一部分都做了超级拆解，不然文件太长了真有点看不下去

**主配置文件**：

- `config.scm` - 系统级主配置文件，加载并组合系统配置模块
- `home-config.scm` - Home 环境主配置文件，加载并组合 Home 配置模块

**全局配置** (`configs/` 根目录)：

- `channel.scm` - 定义 Guix 软件包频道
- `information.scm` - 定义系统基本信息

**系统配置模块** (`configs/system/` 目录)：

- `modules.scm` - 导入系统配置所需的 Guix 模块
- `bootloader.scm` - 配置引导加载器（GRUB/UKI）
- `filesystems.scm` - 配置文件系统挂载点和 Btrfs 子卷
- `kernel.scm` - 配置内核版本、微码、固件和内核参数
- `luks.scm` - 配置 LUKS 磁盘加密和映射设备
- `packages.scm` - 定义系统要安装的软件包列表
- `services.scm` - 配置系统级服务（网络、音频、显示管理等）
- `users.scm` - 配置系统时区、语言环境、主机名和用户账户

**Home 配置模块** (`configs/home/` 目录)：

- `modules.scm` - 导入 Home 配置所需的 Guix 模块
- `package.scm` - 定义用户环境的软件包列表
- `services/desktop.scm` - 配置桌面环境所需要的一些服务
- `services/dotfile.scm` - 配置其他软件所使用的配置文件
- `services/environment-variables.scm` - 配置用户环境变量
- `services/font.scm` - 配置用户字体设置

## 使用方法

### 部署系统配置

```bash
# 重新配置系统
sudo guix system reconfigure config.scm
```

### 部署 Home 配置

```bash
# 重新配置 Home 环境
guix home reconfigure home-config.scm
```

### 更新频道和软件包

```bash
# 拉取频道更新
guix pull

# 更新系统
guix system reconfigure config.scm

# 更新 Home
guix home reconfigure home-config.scm
```

### 特别感谢

Grok：帮我解决问题
GLM：帮忙拆分了一下我的配置文件
[GNU/Guix China群聊](https://t.me/guixcn)：帮助解决了进入系统的大问题，才终于让我用上了Guix

---

**日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。**--《日常》
