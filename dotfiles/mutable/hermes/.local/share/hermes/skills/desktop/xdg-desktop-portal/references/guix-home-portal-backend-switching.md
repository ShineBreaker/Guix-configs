# Guix Home + niri 环境下 XDG Portal 后端切换

> 适用场景：在 Guix Home + niri 环境下切换默认 portal 后端（wlr ↔ gnome），或排查 portal 接口（截图/屏幕共享/设置）失效。

## 三处必须同步的位置

Portal 后端切换必须同时改三处，否则会出现"包装了没启动"或"启动了但 portals.conf 没选"的割裂：

| 位置 | 文件 | 作用 |
| ---- | ---- | ---- |
| **A. portals.conf** | `dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf` | 声明默认后端 + 各接口优先级 |
| **B. packages 列表** | `source/config.org` 的 `user-packages` 块 | 声明安装的 portal 包 |
| **C. shepherd 服务** | `source/config.org` 的 `home-shepherd-services` 块 | 声明自启动的 portal daemon |

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

## GNOME portal 在 niri 下的已知限制

GNOME portal 的 **ScreenCast** 和 **Screenshot** 接口依赖 GNOME Shell 的内置实现，在 niri 下**不工作**（即使装了 `xdg-desktop-portal-gtk` 也只会 fallback 到 gtk 实现，gtk 实现不支持 wayland 截图）。

**切换前必问用户**：

| 方案 | default 值 | ScreenCast/Screenshot | 适用场景 |
| ---- | ---------- | --------------------- | -------- |
| 全切 gnome | `gnome;gtk` | ❌ 不可用 | 不需要截图/录屏，或愿意用第三方工具（grim/slurp） |
| gnome + wlr 兜底 | `gnome;gtk` + 接口级 wlr | ✅ wlr 处理 | 想要 gnome 的设置/通知，但截图走 wlr |
| 全 wlr | `wlr;gtk` | ✅ wlr 处理 | niri 默认，功能最全 |

## 切换流程（以 wlr → gnome 为例）

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

# 看 portals.conf 是否被读（通过 dbus 查询）
dbus-send --session --print-reply --dest=org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.DBus.Properties.Get \
  string:org.freedesktop.portal.Settings string:version 2>&1

# 截图测试（验证 Screenshot portal 是否工作）
# gnome: 应该弹 gnome-shell 的截图 UI
# wlr: 应该弹 grim/slurp 的区域选择光标
```

## 反模式

- ❌ **只改 portals.conf 不改 packages** → 报 "no implementation for wlr"（包没了但 conf 还在选）
- ❌ **只改 packages 不改 shepherd** → portal daemon 没自启动，需要手动跑
- ❌ **只改 shepherd 不改 packages** → 启动失败（二进制不存在）
- ❌ **装多个 portal 但 conf 里只写一个** → 多余的 daemon 抢接口，行为不确定
- ❌ **在 niri 下期望 gnome portal 的 ScreenCast 工作** → 不可能，这是上游限制

## 实战记录（2026-07-27）

用户要求从 wlr 全切到 gnome。改动：

1. `dotfiles/immutable/desktop/.config/xdg-desktop-portal/portals.conf`：
   - 删除 `org.freedesktop.impl.portal.ScreenCast=wlr` 等 wlr 特有行
   - `default=wlr;gtk` → `default=gnome;gtk`

2. `source/config.org` packages 列表：
   - 删除 `"xdg-desktop-portal-wlr"`

3. `source/config.org` `home-shepherd-services` 块：
   - 删除 `(make-shepherd-service xdg-desktop-portal-wlr "/libexec/xdg-desktop-portal-wlr" '(graphical-session))`

验证：`blue check` 全部通过，portals.conf INI 解析正常，无 wlr 残留引用。
