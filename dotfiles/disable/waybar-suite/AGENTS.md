# waybar-suite（已弃用）

> 本目录保留 `waybar` 时期的完整主题套件（含 darkman、waybar、fuzzel、mako、swayidle、swaylock），**不再部署**。已由 `noctalia-suite` + `desktop` 替代。
>
> structor 树中的 `desktop-suite/` 是旧名称残留，实际目录名为 `waybar-suite/`。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 blue structor 自动维护，请勿手改 -->

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

此配置保留以供参考，不纳入 `dotfile-services` 的 `packages` 列表。
