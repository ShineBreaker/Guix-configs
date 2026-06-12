# WM 主题套件配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。与 `desktop/` 中的"功能性"配置相对，本目录集中管理"主题外观"相关配置。

## 目录结构

```
desktop-suite/.config/
├── darkman/
│   ├── config/                          # 各应用主题配置（darkman 通过目录复制）
│   │   ├── fuzzel/themes.ini
│   │   ├── gtk-3.0/settings.ini
│   │   ├── gtk-4.0/settings.ini
│   │   ├── kitty/theme.conf
│   │   ├── Kvantum/kvantum.kvconfig
│   │   ├── mako/theme
│   │   ├── qt5ct/qt5ct.conf
│   │   ├── qt6ct/qt6ct.conf
│   │   └── waybar/colors.css
│   └── script/
│       ├── config.json                  # darkman 脚本配置
│       └── set-theme.sh                 # 主题切换脚本
├── foot/
│   └── themes/material.ini              # foot 终端主题
├── fuzzel/
│   └── fuzzel.ini                       # 应用启动器
├── mako/
│   └── config                           # 通知守护进程
├── niri/
│   └── settings/
│       └── key-bindings-wm.kdl          # niri WM 主题/工作区相关快捷键
├── swayidle/
│   └── config                           # 空闲管理
├── swaylock/
│   └── config                           # 锁屏
└── waybar/
    ├── config.jsonc                     # 状态栏
    └── style.css

desktop-suite/.local/
└── share/
    ├── dark-mode.d/
    │   └── 0-apply-theme.sh             # 切换到暗色时执行
    ├── light-mode.d/
    │   └── 0-apply-theme.sh             # 切换到亮色时执行
    └── icons/
        └── default/
            └── index.theme              # 默认图标主题
```

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