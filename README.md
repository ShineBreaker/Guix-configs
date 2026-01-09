# Guix 配置仓库

这是我的 GNU Guix 系统配置和 Home 环境配置文件。

## 项目简介

本项目包含了使用 GNU Guix 构建的个人 Linux 系统配置，包括系统级配置和 Home 环境配置。配置使用了多个第三方频道来扩展 Guix 的包库。

## 系统特性

### 核心配置

- **发行版**: GNU Guix System
- **内核**: Linux XanMod
- **时区**: Asia/Shanghai
- **语言环境**: zh_CN.utf8
- **Shell**: Fish

### 桌面环境

- **显示服务器**: Wayland
- **窗口合成器**: Niri（动态平铺式 Wayland 合成器）
- **显示管理器**: SDDM（自动登录）
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

### 主要软件包

#### 系统工具

- `podman`, `podman-compose` - 容器管理
- `distrobox` - 容器化开发环境
- `flatpak` - 跨发行版应用分发
- `mihomo` - 代理服务（后台守护进程运行）

#### 开发工具

- `helix` - 现代文本编辑器
- `git` - 版本控制
- `python` - Python 编程语言
- `fish` - 友好的交互式 shell
- `starship` - 优秀的 shell 提示符
- `zoxide` - 智能目录跳转
- `eza` - 更好的 ls 替代品
- `bat` - cat 的增强版
- `btop` - 系统监控工具
- `fzf` - 命令行模糊查找器

#### 多媒体

- `pipewire` - 音频服务器
- `wireplumber` - PipeWire 会话管理
- `easyeffects` - 音频效果处理
- `nomacs` - 图像查看器

#### 游戏娱乐

- `steam` - Steam 游戏平台
- `prismlauncher-dolly` - Minecraft 启动器
- `libreoffice` - 办公套件

#### 网络与代理

- `mihomo` - 代理内核
- 系统级 HTTP/HTTPS 代理配置（127.0.0.1:7890）

### 内核优化

配置了多项内核参数以提升系统性能：

- 启用 zswap 压缩交换
- 网络优化：BBR 拥塞控制、TCP 快速打开
- 虚拟内存优化：减少缓存压力、降低页锁不公平性
- 禁用 NUMA 平衡、启用调度自动分组

### 自定义频道

使用以下第三方频道扩展包库：

- **cast** - 包含 GTK 锁屏器等
- **nonguix** - 非 100% 自由软件
- **radix** - 额外软件包
- **rde** - Reproducible Development Environment
- **rosenthal** - 提供多种额外包
- **saayix** - 二进制包和字体
- **sops-guix** - Secrets 管理集成

### 字体配置

- **无衬线字体**: Sarasa Gothic SC（更纱黑体 SC）
- **等宽字体**: Iosevka Nerd Font Mono
- **Emoji**: Noto Color Emoji
- **图标**: Font Awesome

### 系统服务

- `nftables` - 防火墙
- `tlp` - 笔记本电源管理
- `rootless-podman` - 无根容器
- `mihomo-daemon` - 代理守护进程
- `syncthing` - 文件同步
- `blueman-applet` - 蓝牙管理

## Home 配置

Home 配置通过 `guix home` 管理，包含：

- 用户级软件包配置
- Fish Shell 配置（包含日文欢迎语）
- Fcitx5 输入法配置
- GPG Agent 配置
- PipeWire 用户级服务
- Niri Wayland 合成器配置
- 环境变量配置
- 字体配置（fontconfig）

## 文件结构

```
.
├── config.scm              # 系统级配置文件
├── home-config.scm         # Home 环境配置文件
├── configs/
│   └── channel.scm         # Guix 频道配置
└── dotfiles/               # 用户配置文件
    └── .gtkrc-2.0
```

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

## 替代源

配置了以下替代源以加速软件包下载：

- https://mirror.sjtu.edu.cn/guix（上海交通大学）
- https://cache-cdn.guix.moe（Moe 缓存）
- https://substitutes.nonguix.org（Nonguix 替代源）

## 系统要求

- UEFI 固件
- 支持 UEFI 的系统
- 至少一个加密分区（LUKS）
- Btrfs 文件系统支持

## 注意事项

1. 此配置针对特定的硬件和用户设置进行了定制
2. 用户名为 `brokenshine`，如果需要使用，请相应修改
3. 磁盘 UUID 和加密密钥文件路径需要根据实际情况调整
4. 代理服务配置在 127.0.0.1:7890，确保 Mihomo 正确配置

## 许可证

本配置文件可自由使用和修改。

## 贡献

欢迎提出建议和改进！

---

**每日提示**：日常生活的每一天，也许都是奇迹的连续。 — Fish Shell 欢迎语
