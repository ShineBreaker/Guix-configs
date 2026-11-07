# 桌面环境配置

本目录部署到 `~/.config/` 与 `~/.local/`，覆盖 Niri、xdg-desktop-portal、PCManFM 与 Rofi；软件包清单见 `source/config.org` 的 `desktop-packages-list` 与相关 service 块。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
desktop/
├── .config/
│   ├── niri/
│   ├── pcmanfm-qt/
│   ├── rofi/
│   ├── swappy/
│   ├── xdg-desktop-portal/
│   └── xfce4/
└── .local/
    └── bin/
```

<!-- /structor -->

## 关键约定

- **Niri 分层**：`config.kdl` 只做顶层装配，`settings/` 下每个子模块单独一个文件并用 `include` 引入，`optional=true` 的条目允许缺省。
- **Portal 后端**：`portals.conf` 默认 `default=gnome;gtk;`，其中 `Secret` 走 gnome-keyring、`Settings` 走 nosdshell（`nosd-helpers portal` daemon，darkman 兼容见 `docs/scripts/desktop/darkman-theme.md`）。
- **截图（grim + slurp + swappy）**：选区截图由 `~/.local/bin/niri-screenshot` 完成（`grim -g "$(slurp)" - | swappy -f -`），键位 `Print` / `Mod+Shift+S`。swappy 内 `Ctrl+C` 复制到剪贴板、`Ctrl+S` 保存到 `~/Pictures/Screenshots`（`early_exit=true` 使首个动作后退出）。niri 原生 `screenshot-window`（`Alt+Print`）与 `screenshot-screen`（`Ctrl+Print`）负责窗口/整屏直存。窗口/整屏截图的保存路径在 `config.kdl` 的 `screenshot-path`。swappy 的 GTK 窗口是常规 xdg toplevel，仅需浮窗规则（`settings/window-rules.kdl`）。此前 flameshot 方案（patch + 浮窗 hack）已整体移除：其 Qt 截图窗口在 niri 的 fractional-scale 下存在 buffer 取整露边、BypassWindowManagerHint 导致的布局滚动等问题，layer-shell 化属上游未实现（flameshot issues #3757/#4948）。
- **自启动**：桌面自启动由 `config.org` 的 shepherd 服务承担，本包不放 `.config/autostart`。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本）。
- **Niri 支持热重载**：`niri msg action load-config-file`，改完即时验证，无需重启会话。
- **其余走重启**：portal 与 PCManFM 偏好在进程启动时读取，改动随 `blue home` 部署，重启对应组件或重新登录才生效。
