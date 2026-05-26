# 桌面环境配置

通过 Guix Home 部署到 `~/.config/`。

## 结构

```
desktop/.config/
├── autostart/           # XDG 自启动项
│   ├── kdeconnect-indicator.desktop
│   ├── net.opentabletdriver.OpenTabletDriver.desktop
│   └── xdg-desktop-portal{,-gnome,-gtk}.desktop
├── niri/                # Wayland 合成器
│   ├── config.kdl           # 主配置
│   └── settings/
│       ├── key-bindings.kdl       # 快捷键
│       └── key-bindings-noctalia.kdl  # Noctalia 主题快捷键（已禁用）
├── pcmanfm-qt/default/  # PCManFM-QT 文件管理器
├── xdg-desktop-portal/  # Portal 配置
│   └── portals.conf
└── xfce4/helpers.rc     # XFCE 默认应用
```

## 关键约定

- niri 配置分为主配置 + settings/ 子目录，通过 `include` 引入
- `key-bindings-noctalia.kdl` 属于已禁用的 Noctalia 主题，保留供参考
- autostart 项使用 XDG 标准 `.desktop` 文件
- portal 配置指定使用 GNOME/GTK 后端

## 修改约束

- niri 配置修改后需 `maak home` 重新部署
- 新增 autostart 项需确保对应服务已安装
