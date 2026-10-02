# 桌面环境配置

本目录部署到 `~/.config/` 与 `~/.local/`，覆盖 Niri、autostart、xdg-desktop-portal、PCManFM 与 Rofi；软件包清单见 `source/config.org` 的 `desktop-packages-list` 与相关 service 块。

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

## 关键约定

- **Niri 分层**：`config.kdl` 只做顶层装配，`settings/` 下每个子模块单独一个文件并用 `include` 引入，`optional=true` 的条目允许缺省。
- **Portal 后端**：`portals.conf` 默认 `default=gnome;gtk;`，其中 `Secret` 走 gnome-keyring、`Settings` 走 darkman。
- **Autostart**：新增 `.desktop` 前先确认目标程序已在 `config.org` 的用户包清单声明，否则条目存在但拉不起二进制。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本）。
- **Niri 支持热重载**：`niri msg action reload-config`，改完即时验证，无需重启会话。
- **其余走重启**：portal、autostart、PCManFM 偏好在进程启动时读取，改动随 `blue home` 部署，重启对应组件或重新登录才生效。
