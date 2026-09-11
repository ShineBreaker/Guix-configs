# 桌面环境配置

本目录通过 Guix Home 的 `home-dotfiles-service-type`（stow 布局）部署到 `~/.config/` 与 `~/.local/`。涉及的软件包清单定义于 `source/config.org` 的 `desktop-packages-list` 与相关 service 块中。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
desktop/
├── .config/
│   ├── autostart/
│   ├── niri/
│   ├── pcmanfm-qt/
│   ├── rofi/
│   ├── xdg-desktop-portal/
│   └── xfce4/
└── .local/
    └── bin/
```

<!-- /structor -->

## 关键约定与分工

- **Niri 窗口管理器**：主配置文件拆分为顶层配置与 `settings/` 子目录，通过 `include` 语法引入各个子模块。
- **自启动项（Autostart）**：遵循 XDG 标准，使用 `.desktop` 文件管理自启应用。
- **Portal 与辅助服务**：`xdg-desktop-portal` 声明使用 GNOME/GTK 后端；XFCE `helpers.rc` 提供系统级默认应用关联。

## 修改与生效流程

1. **改源后生效**：修改仓库源码后，运行 `blue home` 重新链接到 Store 只读副本（请勿直接编辑 `~/.config/` 下的部署文件）。
2. **Niri 热重载**：Niri 配置文件支持免重启热加载，执行 `niri msg action reload-config` 即可。
3. **依赖校验**：新增自启动项（`.desktop`）前，需确认对应程序已在 `config.org` 的用户包清单中声明。
