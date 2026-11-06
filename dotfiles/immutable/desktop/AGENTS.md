# 桌面环境配置

本目录部署到 `~/.config/` 与 `~/.local/`，覆盖 Niri、xdg-desktop-portal、PCManFM 与 Rofi；软件包清单见 `source/config.org` 的 `desktop-packages-list` 与相关 service 块。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
desktop/
├── .config/
│   ├── flameshot/
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
- **Portal 后端**：`portals.conf` 默认 `default=gnome;gtk;`，其中 `Secret` 走 gnome-keyring、`Settings` 走 nosdshell（`nosd-helpers portal` daemon，darkman 兼容见 `docs/scripts/desktop/darkman-theme.md`）。
- **截图（flameshot）**：安装的是打补丁的 `flameshot-niri`（派生定义见 `source/config.org` 自定义包，补丁 `source/files/patches/flameshot-niri-wayland.patch`），三处修补：补 `app_id` 让 niri 窗口规则能匹配（`open-fullscreen true` + 去圆角）；grim 适配器按「图高 / 屏幕逻辑几何高」设 DPR（Qt 的 `devicePixelRatio()` 在 1.75 缩放下返回 2，直接用会让截图只占屏幕 87.5%）；Wayland 复制改走 `wl-copy --type image/png`，否则 flameshot 退出后 Qt 剪贴板数据源随之消失。niri 下没有可用的 Screenshot portal 后端，flameshot 只能走 grim 适配器，配置里 `useGrimAdapter=true`。
- **自启动**：桌面自启动由 `config.org` 的 shepherd 服务承担，本包不放 `.config/autostart`。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本）。
- **Niri 支持热重载**：`niri msg action load-config-file`，改完即时验证，无需重启会话。
- **其余走重启**：portal 与 PCManFM 偏好在进程启动时读取，改动随 `blue home` 部署，重启对应组件或重新登录才生效。
