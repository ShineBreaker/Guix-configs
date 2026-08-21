# GTK Portal 上游移除 OpenURI 支持

## 背景

`xdg-desktop-portal-gtk` 从 **1.15.0** 版本起移除了 `org.freedesktop.impl.portal.AppChooser` 和 OpenURI 相关接口。

## 上游理由

GTK/GNOME 维护者认为：打开 URI/文件应由应用直接调用 GAppInfo API（`g_app_info_launch_default_for_uri` / `g_app_info_get_default_for_type`），而非通过 portal 间接调用。

## 影响范围

- **flatpak 应用**：flatpak runtime 内置的 `xdg-open` (1.0.6+) 会优先通过 portal 的 `OpenURI` 接口打开文件/URL
- **所有 wlroots 系 compositor**：niri、sway、Wayfire、Hyprland 等通常只用 `xdg-desktop-portal-wlr`（仅 Screenshot/ScreenCast），不会安装 GTK portal
- **混合环境**：即使同时安装了 GTK portal，1.15.x+ 版本也不会注册 OpenURI 接口

## 接口状态对照

| Backend | 版本 | AppChooser | Email | OpenURI |
|---------|------|-----------|-------|---------|
| xdg-desktop-portal-gtk | 1.14.1 | ✅ | ✅ | ✅ |
| xdg-desktop-portal-gtk | 1.15.0+ | ❌ | ✅ | ❌ |
| xdg-desktop-portal-gtk | 1.15.3 | ❌ | ✅ | ❌ |
| xdg-desktop-portal-wlr | 0.8.2 | ❌ | ❌ | ❌ |
| xdg-desktop-portal-kde | 6.5.5 | ✅ | ✅ | ❌ |
| xdg-desktop-portal-gnome | 48.0 | ✅ | ✅ | ❌ |

注意：KDE/GNOME portal 虽然注册了 `AppChooser` 接口，但它们**也不实现 OpenURI**。`AppChooser` 是用于"选择哪个应用打开"的对话框，与 OpenURI 不同。flatpak 的 xdg-open 需要的是 OpenURI 接口。

## 检测方法

```bash
# 检查当前 portal 注册了哪些接口
dbus-send --session --print-reply \
  --dest=org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop \
  org.freedesktop.DBus.Introspectable.Introspect | grep "interface name"

# 检查 GTK portal 版本
find /gnu/store -name "gtk.portal" 2>/dev/null | head -1 | xargs cat
```

## 修复路径

参见 SKILL.md 的"方案 B：编写最小 OpenURI backend"一节。

核心思路：自己实现一个 D-Bus 服务，注册 `org.freedesktop.portal.OpenURI` 接口，内部调用 `g_app_info_launch_default_for_uri`（URL）或 `g_app_info_get_default_for_type` + `g_app_info_launch`（本地文件）。
