---
name: xdg-desktop-portal
description: "Diagnose and fix xdg-desktop-portal backend issues — especially when sandboxed apps (flatpak, snap) can't open files/URLs via xdg-open."
triggers:
  - flatpak xdg-open fails
  - sandboxed app cannot open file or URL
  - portal interface missing
  - xdg-desktop-portal backend not registering interface
  - OpenURI AppChooser not available
  - XDG_SESSION_TYPE=tty portal settings only
  - gnome portal Non-compatible display server
  - obs screen capture not working niri
  - xdg-desktop-portal-gnome only exposing settings
---

# xdg-desktop-portal 诊断与修复

## 架构速览

```
sandboxed app → xdg-open → D-Bus call to /org/freedesktop/portal/desktop
                         → xdg-desktop-portal (中央守护进程)
                         → 路由到具体 backend 实现
```

- 中央守护进程：xdg-desktop-portal（接收所有 portal 请求，按接口名路由）
- Backend 实现：各自独立的 D-Bus 服务，在 .portal 文件中声明自己支持哪些接口
- 路由规则：由 ~/.config/xdg-desktop-portal/portals.conf 和各 backend 的 .portal 文件中的 UseIn= 字段共同决定

## 诊断流程

### 1. 检查当前运行的 portal 后端

```bash
pgrep -fa xdg-desktop-portal
```

### 2. 检查所有已安装的 backend 及其支持的接口

```bash
find ~/.guix-home/profile /run/current-system/profile /gnu/store \
  -name "*.portal" 2>/dev/null | while read f; do
  echo "--- $f ---"; cat "$f"
done
```

重点关注 Interfaces= 行，看是否包含你需要的接口。

### 3. 检查 portal 实际注册了哪些 D-Bus 接口

```bash
dbus-send --session --print-reply \
  --dest=org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop \
  org.freedesktop.DBus.Introspectable.Introspect | grep "interface name"
```

如果 org.freedesktop.portal.OpenURI 不在列表中，说明没有 backend 注册它。

### 4. 测试 xdg-open 调用链

```bash
flatpak run --command=sh <app-id> -c 'xdg-open https://example.com'
```

常见错误：
- UnknownMethod → 没有 backend 实现该接口
- no method available → backend 存在但无法处理

## 已知问题：GTK portal 1.15.x 移除 OpenURI

现象：xdg-desktop-portal-gtk 从 1.15.0 起彻底移除了 org.freedesktop.impl.portal.AppChooser 和 OpenURI 支持。上游认为应用应直接调用 GAppInfo 而非通过 portal。

确认方法：
```bash
cat /gnu/store/*-xdg-desktop-portal-gtk-*/share/xdg-desktop-portal/portals/gtk.portal | grep Interfaces
```

如果版本 >= 1.15.0 且不含 AppChooser，即可确认。

## 修复方案

### 方案 A：安装支持 OpenURI 的 backend

```bash
guix package -A | grep portal
```

注意：截至 2026 年，xdg-desktop-portal-kde (6.5.5)、xdg-desktop-portal-gnome (48.0) 也都不支持 OpenURI。如果都不支持，走方案 B。

### 方案 B：编写最小 OpenURI backend

当所有上游 backend 都放弃 OpenURI 时，自行实现一个最小 backend。

最小实现只需支持 OpenURI 方法（OpenFile 仅旧版 flatpak 需要）：

核心逻辑：
1. 收到 OpenURI 调用，解析 (parent_window, uri, options)
2. 如果 uri 以 file:// 开头：
   - 用 g_filename_from_uri 转为路径
   - 用 g_file_query_info 获取 content-type
   - 用 g_app_info_get_default_for_type 找默认应用
   - 用 g_app_info_launch 打开
3. 否则（http/https 等）：
   - 用 g_app_info_launch_default_for_uri 打开

编译命令（Guix 环境，需指定 GLib 路径）：

```bash
GLIB=/gnu/store/25dylanmcbv8jxmljznhjhjra14rz11q-glib-2.86.0
gcc -o openuri-portal openuri-portal.c \
  -I$GLIB/include/glib-2.0 \
  -I$GLIB/lib/glib-2.0/include \
  -L$GLIB/lib \
  -Wl,-rpath,$GLIB/lib \
  -lglib-2.0 -lgio-2.0 -lgobject-2.0
```

注册 backend：

1. 创建 .portal 描述文件 ~/.local/share/xdg-desktop-portal/portals/openuri.portal：
   [portal]
   DBusName=org.freedesktop.impl.portal.desktop.openuri
   Interfaces=org.freedesktop.impl.portal.AppChooser;org.freedesktop.impl.portal.Email;
   UseIn=*

2. 创建 D-Bus service 文件 ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.openuri.service：
   [D-BUS Service]
   Name=org.freedesktop.impl.portal.desktop.openuri
   Exec=/path/to/openuri-portal

3. 更新 ~/.config/xdg-desktop-portal/portals.conf：
   [preferred]
   default=wlr;gtk
   org.freedesktop.impl.portal.AppChooser=openuri
   org.freedesktop.impl.portal.Email=openuri

4. 重启 portal：
   systemctl --user restart xdg-desktop-portal

## 陷阱与注意事项

1. GLib 版本差异：g_dbus_method_invocation_get_unix_fd_list 在 GLib 2.86.0 中可能不可用。如果只需要支持 OpenURI（大多数情况），可以跳过 OpenFile 实现，避免 fd_list 处理。

2. D-Bus 名称抢占：G_BUS_NAME_OWNER_FLAGS_REPLACE 会替换同名服务，确保你的 backend 名称唯一。

3. flatpak xdg-open 版本：flatpak 1.16.6 自带的 xdg-open (1.0.6) 使用 OpenURI 而非 OpenFile，所以最小实现只需覆盖 OpenURI。

4. Guix profile 路径：编译时 GLib 路径会随 store hash 变化，用 find /gnu/store -name "libglib-2.0.so" | head -1 定位。

5. 验证注册是否成功：
   dbus-send --session --print-reply \
     --dest=org.freedesktop.portal.Desktop \
     /org/freedesktop/portal/desktop \
     org.freedesktop.DBus.Introspectable.Introspect | grep -i openuri

## niri 下 ScreenCast/Screenshot 修复（后端路由方案）

### niri 下各 portal 后端的实际接口（2026-07-28 实测）

通过 `busctl --user introspect` 在 niri 25.x 环境下实测：

| 后端 | 包名 | 实际提供的接口 | 原因 |
|------|------|---------------|------|
| gnome | `xdg-desktop-portal-gnome` | **仅 Settings** | 缺少 Mutter ServiceChannel（`org.gnome.Mutter.ServiceChannel`） |
| gtk | `xdg-desktop-portal-gtk` | FileChooser/Access/Notification/Lockdown/Print/Wallpaper | `.portal` 文件未声明 ScreenCast/Screenshot |
| wlr | `xdg-desktop-portal-wlr` | ScreenCast/Screenshot/RemoteDesktop | 通过 wlr-screencopy 协议 |

### 根因

- **gnome portal**：`libgxdp/src/gxdp-wayland.c:236` 的 `gxdp_wayland_init()` 尝试连接 `org.gnome.Mutter.ServiceChannel` 获取 Wayland fd，niri 不提供该接口 → 降级到 `init_gtk_wayland_fallback()` → 只导出 Settings。**上游限制，非配置问题**。
- **gtk portal**：`.portal` 文件的 Interfaces 列表里没有 ScreenCast/Screenshot。

### niri 下的完整路由方案

```ini
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Settings=darkman
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.RemoteDesktop=wlr
```

### 三处必须同步

| 位置 | 文件 | 作用 |
|------|------|------|
| portals.conf | `dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf` | 声明后端优先级 |
| packages 列表 | `source/config.org` 的 `user-packages` 块 | 声明安装的 portal 包 |
| shepherd 服务 | `source/config.org` 的 `home-shepherd-services` 块 | 声明自启动的 portal daemon |

### `GDK_BACKEND=wayland` 全局陷阱

niki wiki 原文：*"Do not set the GDK_BACKEND environment variable globally as this will break the screencast portal."*

如果 `config.org` 里有 `("GDK_BACKEND" . "wayland")` 全局声明，需要删掉——让 GTK 应用自动选择 Wayland。

### `putenv` 模式 — 给单个 portal 注入环境变量

```scheme
(simple-service 'xdg-desktop-portal-gnome home-shepherd-service-type
  (list (shepherd-service
         (provision '(xdg-desktop-portal-gnome))
         (requirement '(xdg-desktop-portal))
         (start #~(lambda args
                    (putenv "XDG_CURRENT_DESKTOP=gnome")
                    ((make-forkexec-constructor
                      (list #$(file-append xdg-desktop-portal-gnome "/libexec/xdg-desktop-portal-gnome"))
                      #:environment-variables (environ)
                      #:log-file (string-append (getenv "XDG_STATE_HOME")
                                                "/shepherd/xdg-desktop-portal-gnome.log"))
                     args)))
         (stop #~(make-kill-destructor))
         (respawn? #t))))
```

**注意**：即使设了 `XDG_CURRENT_DESKTOP=gnome`，gnome portal 在 niri 下仍然只提供 Settings。

### 验证命令

```bash
# 看各 backend 注册了哪些接口
busctl --user introspect org.freedesktop.impl.portal.desktop.gnome /org/freedesktop/portal/desktop | grep interface
busctl --user introspect org.freedesktop.impl.portal.desktop.gtk /org/freedesktop/portal/desktop | grep interface
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep interface

# 看 portal 进程在跑什么
pgrep -af xdg-desktop-portal

# 看 D-Bus 名占用
busctl --user list | grep -i portal
```
