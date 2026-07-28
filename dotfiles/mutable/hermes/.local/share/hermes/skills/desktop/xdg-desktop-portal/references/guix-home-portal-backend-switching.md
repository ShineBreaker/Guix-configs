# Guix Home + niri 环境下 XDG Portal 后端切换

> 适用场景：在 Guix Home + niri 环境下切换默认 portal 后端（wlr ↔ gnome），或排查 portal 接口（截图/屏幕共享/设置）失效。

## 架构：D-Bus 自动激活（不需要手写 shepherd 服务）

Testament 仓库（`~/Projects/Config/Testament`）**没有手写 portal 的 shepherd 服务**——portal 后端通过 D-Bus service 文件自动激活：

```
~/.guix-home/profile/share/dbus-1/services/
├── org.freedesktop.impl.portal.desktop.gnome.service
├── org.freedesktop.impl.portal.desktop.gtk.service
└── org.freedesktop.portal.Desktop.service
```

当 app 发 D-Bus 请求到 `org.freedesktop.portal.Desktop`，主 portal 进程启动，读取 `portals.conf` 决定用哪个 backend，然后通过 D-Bus 激活对应 backend（`Name=org.freedesktop.impl.portal.desktop.gnome` → 启动 `xdg-desktop-portal-gnome`）。

**Guix-configs 仓库的写法不同**：它在 `home-shepherd-services` 块里显式起了 portal daemon。两种写法都可行，但 Testament 的 D-Bus 自动激活更简洁、少维护 shepherd 定义。

## 三处必须同步的位置

Portal 后端切换必须同时改三处，否则会出现"包装了没启动"或"启动了但 portals.conf 没选"的割裂：

| 位置 | 文件 | 作用 |
| ---- | ---- | ---- |
| **A. portals.conf** | `dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf` | 声明默认后端 + 各接口优先级 |
| **B. packages 列表** | `source/config.org` 的 `user-packages` 块 | 声明安装的 portal 包 |
| **C. shepherd 服务** | `source/config.org` 的 `home-shepherd-services` 块 | 声明自启动的 portal daemon（如果用 Guix-configs 写法） |

## portals.conf 语法

INI 格式，`[preferred]` 段。`default` 是分号分隔的 fallback 链（先试第一个，失败试第二个）。键名是 portal 接口的 reverse-DNS，值是实现 ID（通常跟包名后缀一致）。

```ini
[preferred]
default=gnome;gtk
org.freedesktop.impl.portal.Settings=darkman
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.RemoteDesktop=wlr
```

**实现 ID 对照**：

| 包名 | 实现 ID |
| ---- | ------- |
| `xdg-desktop-portal-gnome` | `gnome` |
| `xdg-desktop-portal-gtk` | `gtk` |
| `xdg-desktop-portal-wlr` | `wlr` |

## GNOME portal 在 niri 下的限制（源码级）

### 限制 1：ScreenCast/Screenshot 不工作

GNOME portal 的 ScreenCast 和 Screenshot 接口依赖 GNOME Shell 的 `org.gnome.Mutter.ServiceChannel` D-Bus 接口。niri 不提供此接口 → gnome portal 在 niri 下**只能暴露 Settings 接口**。

日志特征：
```
Failed to open service channel Wayland connection, portals dialogs may missbehave
(无法调用方法；代理名称为常见的无所有者的名称 org.gnome.Mutter.ServiceChannel)
```

`busctl --user introspect org.freedesktop.impl.portal.desktop.gnome /org/freedesktop/portal/desktop` 确认只注册了 `org.freedesktop.impl.portal.Settings`。

### 限制 2：`XDG_SESSION_TYPE=tty` 陷阱（本次会话实测根因）

**调用链**：
```
greetd (TTY 显示管理器) → XDG_SESSION_TYPE=tty
  → niri --session (继承 tty)
    → config.kdl: spawn-sh-at-startup "herd set-environment ... XDG_SESSION_TYPE=$XDG_SESSION_TYPE ..."
      → $XDG_SESSION_TYPE 是 "tty" → shepherd 拿到 tty
        → portal 进程继承 XDG_SESSION_TYPE=tty
          → gxdp_init_gtk() 读 getenv("XDG_SESSION_TYPE") → 不是 "wayland" 也不是 "x11"
            → 返回 FALSE → 报 "Non-compatible display server, exposing settings only."
```

`libgxdp/src/gxdp.c:82` 源码：
```c
session_type = getenv("XDG_SESSION_TYPE");
if (g_strcmp0(session_type, "wayland") == 0) { return gxdp_wayland_init(...); }
if (g_strcmp0(session_type, "x11") == 0) { return TRUE; }
// 都不是 → 报错
g_set_error(error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
             "Unsupported or missing session type '%s'", session_type);
return FALSE;  // → settings_only = TRUE
```

**修复**：在 `config.kdl` 的 `environment { }` 块里**直接写死**：
```kdl
environment {
  XDG_CURRENT_DESKTOP "niri"
  XDG_SESSION_TYPE "wayland"
}
```

不要依赖 `$XDG_SESSION_TYPE` 变量展开（它在 niri 自己环境里也是 `tty`）。

## niri 下正确的多后端路由

```ini
[preferred]
default=gnome;gtk
org.freedesktop.impl.portal.Settings=darkman
org.freedesktop.impl.portal.FileChooser=gtk
org.freedesktop.impl.portal.Access=gtk
org.freedesktop.impl.portal.Notification=gtk
org.freedesktop.impl.portal.Secret=gnome-keyring
org.freedesktop.impl.portal.ScreenCast=wlr
org.freedesktop.impl.portal.Screenshot=wlr
org.freedesktop.impl.portal.RemoteDesktop=wlr
```

各后端分工：
- **gnome**：Settings（GNOME Settings）+ Secret（gnome-keyring）
- **gtk**：FileChooser / Access / Notification / Wallpaper 等基础接口
- **wlr**：ScreenCast / Screenshot / RemoteDesktop（**niri 唯一支持的录屏后端**）

**重要**：不要选"全部切 gnome"——删除 wlr portal 会导致 OBS 录屏完全不可用。

## 切换流程

```bash
# 1) 改 portals.conf
#    编辑 dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf
#    default=wlr;gtk → default=gnome;gtk
#    删除 wlr 特有的接口行（ScreenCast/Screenshot/RemoteDesktop）

# 2) 改 source/config.org packages 列表
#    删除 "xdg-desktop-portal-wlr"

# 3) 改 source/config.org home-shepherd-services 块
#    删除 (make-shepherd-service xdg-desktop-portal-wlr ...) 行

# 4) 括号检查
cd ~/Projects/Config/Guix-configs && blue check

# 5) 部署
blue home

# 6) 验证 portals.conf 同步
cat ~/.config/xdg-desktop-portal/portals.conf
# 确认 store hash 变了: readlink ~/.config/xdg-desktop-portal/portals.conf

# 7) 重启 niri 会话（portal daemon 在 session 启动时加载）
pkill -f 'niri --session'
```

## 验证命令

```bash
# 看当前 portal 进程在跑什么
pgrep -af xdg-desktop-portal

# 看各 backend 注册了哪些接口（最直接证据）
busctl --user introspect org.freedesktop.impl.portal.desktop.gnome /org/freedesktop/portal/desktop | grep interface
busctl --user introspect org.freedesktop.impl.portal.desktop.gtk /org/freedesktop/portal/desktop | grep interface
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep interface

# 看 portal 主进程环境变量（确认 XDG_SESSION_TYPE）
tr '\0' '\n' < /proc/$(pgrep -f 'libexec/xdg-desktop-portal$')/environ | grep -E 'XDG_SESSION_TYPE|XDG_CURRENT_DESKTOP'

# 截图测试
# gnome backend: 应该弹 gnome-shell 的截图 UI（niri 下不可用）
# wlr backend: 应该弹 grim/slurp 的区域选择光标
```

## 反模式

- ❌ **只改 portals.conf 不改 packages** → 报 "no implementation for wlr"（包没了但 conf 还在选）
- ❌ **只改 packages 不改 shepherd** → portal daemon 没自启动
- ❌ **只改 shepherd 不改 packages** → 启动失败（二进制不存在）
- ❌ **装多个 portal 但 conf 里只写一个** → 多余的 daemon 抢接口
- ❌ **在 niri 下期望 gnome portal 的 ScreenCast 工作** → 不可能，这是上游限制
- ❌ **依赖 `$XDG_SESSION_TYPE` 变量展开** → niri 环境里是 `tty`，不是 `wayland`
- ❌ **`putenv("XDG_CURRENT_DESKTOP=gnome")` 替代修复 XDG_SESSION_TYPE** → 治标不治本，gnome portal 仍因 SESSION_TYPE=tty 回退

## 实战记录（2026-07-28）

用户要求从 wlr 全切到 gnome，删除了 wlr portal 包和服务。

1. `portals.conf`：`default=gnome;gtk` + 删除 wlr 特有行
2. `config.org` packages：删除 `"xdg-desktop-portal-wlr"`
3. `config.org` shepherd：删除 wlr portal 行

**发现问题**：
- 重启后 gnome portal 报 `Non-compatible display server, exposing settings only.`
- 根因：`XDG_SESSION_TYPE=tty`（greetd → niri → shepherd → portal）
- 修复：`config.kdl` `environment { }` 块写死 `XDG_SESSION_TYPE "wayland"` + `XDG_CURRENT_DESKTOP "niri"`

**后续问题**：
- gnome portal 在 niri 下只能提供 Settings（因缺少 Mutter 的 `org.gnome.Mutter.ServiceChannel`）
- OBS 录屏完全不可用（wlr 被删了，gnome 又不支持）
- 需要把 wlr 加回来，用多后端路由
