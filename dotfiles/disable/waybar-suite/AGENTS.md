# WM 主题套件配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。与 `desktop/` 中的"功能性"配置相对，本目录集中管理"主题外观"相关配置。

## 目录结构

<!-- structor:begin -->

<!-- 此结构图由 blue structor 自动维护，请勿手改 -->

```
desktop-suite/
├── .config/
│   ├── darkman/
│   │   ├── config/
│   │   │   ├── Kvantum/
│   │   │   ├── fuzzel/
│   │   │   ├── gtk-3.0/
│   │   │   ├── gtk-4.0/
│   │   │   ├── kitty/
│   │   │   ├── mako/
│   │   │   ├── qt5ct/
│   │   │   ├── qt6ct/
│   │   │   ├── waybar/
│   │   │   └── .gtkrc-2.0
│   │   └── script/
│   │       ├── config.json
│   │       └── set-theme.sh
│   ├── foot/
│   │   └── themes/
│   │       └── material.ini
│   ├── fuzzel/
│   │   └── fuzzel.ini
│   ├── mako/
│   │   └── config
│   ├── niri/
│   │   └── settings/
│   │       └── key-bindings-wm.kdl
│   ├── swayidle/
│   │   └── config
│   ├── swaylock/
│   │   └── config
│   └── waybar/
│       ├── config.jsonc
│       └── style.css
└── .local/
    └── share/
        ├── dark-mode.d/
        │   └── 0-apply-theme.sh
        ├── icons/
        │   └── default/
        └── light-mode.d/
            └── 0-apply-theme.sh
```

<!-- /structor -->

## 关键约定

- **darkman** 通过 D-Bus 触发主题切换，调用 `~/.local/share/{dark,light}-mode.d/` 中的脚本
- darkman 切换时会按目录原样复制 `~/.config/darkman/config/` 下文件
- GTK3 / GTK4 / Qt5 / Qt6 / Kvantum 主题配置需保持一致
- waybar 使用 JSONC 配置 + CSS 样式分离
- `key-bindings-wm.kdl` 是 niri 的 WM 主题/工作区相关快捷键；与 `desktop/.config/niri/settings/key-bindings.kdl` 是两个独立文件
- `foot/themes/` 仅放主题片段；foot 主配置在 `terminal/.config/foot/foot.ini`

## 修改约束

- 新增主题文件需同步更新 `set-theme.sh` 中的切换逻辑（如需应用感知）
- waybar 配置修改后可用 SIGUSR1 重载：`pkill -SIGUSR1 waybar`
- darkman 配置修改后需 `darkman reload` 或重启 darkman 服务

## 关联文档

- niri 主配置：`dotfiles/enable/desktop/.config/niri/`
- foot 终端主配置：`dotfiles/enable/terminal/.config/foot/`
