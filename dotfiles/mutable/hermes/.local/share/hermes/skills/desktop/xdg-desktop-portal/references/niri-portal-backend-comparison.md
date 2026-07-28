# niri 下 XDG Desktop Portal 后端对比（2026-07-28 实测）

> 实测环境：niri 25.x + gnome portal 48.0 + gtk portal 1.15.3 + wlr portal 0.8.2 + darkman 2.3.0 + gnome-keyring 48.0

## 各后端实际提供的接口

通过 `busctl --user introspect` 实测：

| 后端 | 包名 | 实际提供的接口 | 原因 |
|------|------|---------------|------|
| gnome | `xdg-desktop-portal-gnome` | **仅 Settings** | 缺少 Mutter ServiceChannel |
| gtk | `xdg-desktop-portal-gtk` | FileChooser/Access/Notification/Lockdown/Print/Wallpaper | `.portal` 文件未声明 ScreenCast/Screenshot |
| wlr | `xdg-desktop-portal-wlr` | ScreenCast/Screenshot/RemoteDesktop | 通过 wlr-screencopy 协议 |
| darkman | `darkman` | Settings（暗色模式） | 替代 gnome Settings |
| gnome-keyring | `gnome-keyring` | Secret | 密码管理 |

## 根因分析

### gnome portal 为什么只提供 Settings

`libgxdp/src/gxdp-wayland.c:236` 的 `gxdp_wayland_init()` 尝试连接 `org.gnome.Mutter.ServiceChannel` D-Bus 接口获取 Wayland connection fd。niri 不提供这个接口 → gnome portal 降级到 `init_gtk_wayland_fallback()` → 只导出 Settings 接口。

**这是上游限制，不是配置问题**。即使设 `XDG_CURRENT_DESKTOP=gnOME` 也无济于事（真正卡住它的是 Mutter ServiceChannel 而非 desktop 名）。

### gtk portal 为什么不支持 ScreenCast

gtk portal 的 `.portal` 文件（`share/xdg-desktop-portal/portals/gtk.portal`）声明的 Interfaces 列表里**根本没有** `org.freedesktop.impl.portal.ScreenCast` 和 `org.freedesktop.impl.portal.Screenshot`。

## niri 下的完整路由方案

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

## 三处必须同步

| 位置 | 文件 | 作用 |
|------|------|------|
| portals.conf | `dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf` | 声明后端优先级 |
| packages 列表 | `source/config.org` 的 `user-packages` 块 | 声明安装的 portal 包 |
| shepherd 服务 | `source/config.org` 的 `home-shepherd-services` 块 | 声明自启动的 portal daemon |

## 常见错误

| 错误 | 根因 | 修复 |
|------|------|------|
| `Non-compatible display server, exposing settings only.` | gnome portal 缺少 Mutter ServiceChannel | 用 wlr 做 ScreenCast |
| `Failed to open service channel Wayland connection ... org.gnome.Mutter.ServiceChannel` | 同上 | 用 wlr 做 ScreenCast |
| `Error reading events from display: 断开的管道` | gtk portal Wayland 连接断了（niri 重启后旧进程残留） | 重启 niri 会话 |
| gnome portal 进程没跑 | shepherd 服务被删 / D-Bus 激活未触发 | 检查 shepherd.conf 和 packages 列表 |
| `GDK_BACKEND=wayland` 全局设置 | niki wiki 点名会破 screencast portal | 删掉全局 GDK_BACKEND |

## `putenv` 模式 — 给单个 portal 注入环境变量

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

## Testament 参考

`~/Projects/Config/Testament` 的 dorphine 配置只装了 gnome + gtk，`niri-portals.conf` 里也没有 ScreenCast/Screenshot 路由——因为该仓库**不处理 niri 下的录屏**。如果需要在 niri 下录屏，必须加 wlr。

## niri wiki 原文警告

> Do not set the GDK_BACKEND environment variable globally as this will break the screencast portal.

> These particular portals are configured in niri-portals.conf which must be installed in the correct location.
