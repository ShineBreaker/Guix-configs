### 核心配置

- **发行版**: GNU Guix System
- **内核**: Linux XanMod
- **时区**: Asia/Shanghai
- **语言环境**: zh_CN.utf8
- **Shell**: Fish

### 桌面环境

- **显示服务器**: Wayland
- **窗口合成器**: Niri
- **显示管理器**: SDDM
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
- **等宽字体**: Iosevka Nerd Font Mono
- **Emoji**: Noto Color Emoji

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

---

**日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。**--《日常》
