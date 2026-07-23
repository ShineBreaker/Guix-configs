# 桌面环境配置

通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`。包清单见 `source/config.org` 的 `desktop-packages-list` 与相关 service 块。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
desktop/
├── .config/
│   ├── autostart/
│   │   ├── kdeconnect-indicator.desktop
│   │   └── net.opentabletdriver.OpenTabletDriver.desktop
│   ├── niri/
│   │   ├── settings/
│   │   │   ├── animations.kdl
│   │   │   ├── key-bindings.kdl
│   │   │   └── window-rules.kdl
│   │   ├── app-switcher.json
│   │   └── config.kdl
│   ├── pcmanfm-qt/
│   │   └── default/
│   │       ├── recent-files.conf
│   │       └── settings.conf
│   ├── rofi/
│   │   └── config.rasi
│   ├── xdg-desktop-portal/
│   │   └── portals.conf
│   └── xfce4/
│       └── helpers.rc
└── .local/
    └── bin/
        └── niri-app-switcher
```

<!-- /structor -->

## 关键约定

- niri 配置分主配置 + `settings/` 子目录，通过 `include` 引入
- autostart 使用 XDG `.desktop` 文件；portal 指定 GNOME/GTK 后端
- XFCE helpers.rc 提供默认应用关联

## 修改约束

- 改源后 `blue home` 生效（不要直接编辑 `~/.config/niri/`）
- 新增 autostart 项前确认对应包已在 `config.org` home-packages 中声明
- niri 支持热加载：`niri msg action reload-config`
