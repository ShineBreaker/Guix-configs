<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# WM 主题配置

通过 Guix Home 部署到 `~/.config/` 和 `~/.local/`。

## 结构

```
wm/.config/
├── darkman/             # ★ Darkman 明暗主题切换
│   ├── config/              # 各应用主题配置
│   │   ├── fuzzel/themes.ini
│   │   ├── gtk-3.0/settings.ini
│   │   ├── gtk-4.0/settings.ini
│   │   ├── .gtkrc-2.0
│   │   ├── kitty/theme.conf
│   │   ├── Kvantum/kvantum.kvconfig
│   │   ├── mako/theme
│   │   ├── qt5ct/qt5ct.conf
│   │   ├── qt6ct/qt6ct.conf
│   │   └── waybar/colors.css
│   └── script/
│       ├── config.json          # Darkman 脚本配置
│       └── set-theme.sh         # 主题切换脚本
├── foot/themes/         # Foot 终端主题
│   └── material.ini
├── fuzzel/              # 应用启动器
│   └── fuzzel.ini
├── mako/                # 通知守护进程
│   └── config
├── niri/settings/       # niri WM 主题相关
│   └── key-bindings-wm.kdl
├── swayidle/            # 空闲管理
│   └── config
├── swaylock/            # 锁屏
│   └── config
└── waybar/              # 状态栏
    ├── config.jsonc
    └── style.css

wm/.local/
├── share/
│   ├── dark-mode.d/     # 切换到暗色时执行的脚本
│   │   └── 0-apply-theme.sh
│   ├── icons/default/
│   │   └── index.theme
│   └── light-mode.d/    # 切换到亮色时执行的脚本
│       └── 0-apply-theme.sh
```

## 关键约定

- Darkman 通过 D-Bus 触发主题切换，调用 `dark-mode.d/` 和 `light-mode.d/` 中的脚本
- GTK3/GTK4/Qt5/Qt6 主题配置需保持一致
- waybar 使用 JSONC 配置 + CSS 样式分离
- `key-bindings-wm.kdl` 是 niri 的 WM 专用快捷键，与 desktop/ 中的基础快捷键分离

## 修改约束

- 新增主题文件需同步更新 `set-theme.sh` 中的切换逻辑
- waybar 配置修改后需 `waybar` 重启或发送 SIGUSR1
- Darkman 配置修改后需 `darkman reload`
