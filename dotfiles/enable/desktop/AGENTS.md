# 桌面环境配置

通过 Guix Home 的 `home-dotfiles-service-type`（stow layout）部署到 `~/.config/`。包清单见 `source/config.org` 的 `desktop-packages-list` 与相关 service 块。

## 目录结构

<!-- structor:begin -->

<!-- 此结构图由 maak structor 自动维护，请勿手改 -->

```
desktop/
└── .config/
    ├── autostart/
    │   ├── kdeconnect-indicator.desktop
    │   └── net.opentabletdriver.OpenTabletDriver.desktop
    ├── niri/
    │   ├── settings/
    │   │   ├── key-bindings.kdl
    │   │   └── window-rules.kdl
    │   └── config.kdl
    ├── pcmanfm-qt/
    │   └── default/
    │       ├── recent-files.conf
    │       └── settings.conf
    ├── xdg-desktop-portal/
    │   └── portals.conf
    └── xfce4/
        └── helpers.rc
```

<!-- /structor -->
## 关键约定

- niri 配置分为主配置 + `settings/` 子目录，通过 `include` 引入
- autostart 项使用 XDG 标准 `.desktop` 文件
- portal 配置指定使用 GNOME/GTK 后端
- XFCE helpers.rc 提供默认应用关联

## 修改约束

- 修改后必须 `maak rebuild` 才会生效（不要直接编辑 `~/.config/niri/` 等已部署路径）
- 新增 autostart 项前确认对应服务包已在 `config.org` 的 home-packages 中声明
- niri 配置支持热加载：`niri msg action reload-config`

## 关联文档

- niri 主题快捷键在 `dotfiles/enable/desktop-suite/.config/niri/settings/key-bindings-wm.kdl`（与本目录 `key-bindings.kdl` 是不同文件，分别由 desktop / desktop-suite 部署）
- 主题切换由 `dotfiles/enable/desktop-suite/` 中的 darkman 体系管理