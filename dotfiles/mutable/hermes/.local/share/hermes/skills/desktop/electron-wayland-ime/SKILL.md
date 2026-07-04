---
name: electron-wayland-ime
description: "Diagnose and fix input method (fcitx5) issues in Electron/Chromium apps running under Wayland compositors (niri, sway, Hyprland). Covers XDG desktop override pattern, Electron flag differences across versions, and fcitx5 diagnostic workflow."
version: 1.0.0
platforms: [linux]
metadata:
  tags: [wayland, electron, chromium, fcitx5, ime, input-method, debugging, niri, xdg-desktop, guix]
---

# Electron Wayland 输入法调试与修复

Electron 应用在 wlroots-based Wayland compositor（niri、sway、Hyprland）下输入法不工作时的诊断和修复流程。适用于 fcitx5 输入法框架。

## 触发条件

- 用户报告 Electron/Chromium 应用在 Wayland 下输入法无法使用
- 同样应用从终端启动时有输入法，但从桌面图标/launcher 启动时没有
- `fcitx5-diagnose` 显示 `frontend:wayland_v2 cap:72 focus:0` 且 focus 始终不激活

## 诊断流程

### 1. 环境变量检查（最优先）

```bash
# 检查目标进程的 IME 关键环境变量
cat /proc/$PID/environ | tr '\0' '\n' | grep -iE '^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|WAYLAND_DISPLAY|NIXOS_OZONE|CHROMIUM_FLAGS|GLFW_IM|SDL_IM)=' | sort
```

必需变量：
- `GTK_IM_MODULE=fcitx`
- `QT_IM_MODULE=fcitx`
- `XMODIFIERS=@im=fcitx`
- `WAYLAND_DISPLAY=wayland-1`

如果缺失，按来源补充：niri `environment { }` 块（niri 子进程）、`herd set-environment graphical-session`（shepherd 子进程）、`dbus-update-activation-environment`（D-Bus 激活的进程）。

### 2. 对比正常/异常应用的环境和 cmdline

```bash
# 完整的进程环境 diff
cat /proc/$GOOD_PID/environ | tr '\0' '\n' | sort > /tmp/env-good.txt
cat /proc/$BAD_PID/environ | tr '\0' '\n' | sort > /tmp/env-bad.txt
comm -23 /tmp/env-good.txt /tmp/env-bad.txt  # 正常有但异常没有的变量

# 完整的 cmdline diff
cat /proc/$GOOD_PID/cmdline | tr '\0' ' ' 
cat /proc/$BAD_PID/cmdline | tr '\0' ' '
```

### 3. Electron 版本差异排查

```bash
# 获取 Electron 版本
# 方法1: crashpad handler 的 --annotation=ver=
cat /proc/$PID/cmdline | tr '\0' '\n' | grep 'ver='
# 方法2: 查找二进制中的版本字符串
strings $(readlink -f /proc/$PID/exe) | grep -oP 'Chrome/\d+' | sort -u
```

已知版本差异：
- Electron 37（Chromium 130）：需要 `--ozone-platform=wayland` 强制 + `UseOzonePlatform` feature flag，`--ozone-platform-hint=auto` 在此版本上有 bug
- Electron 41（Chromium 134）：Wayland IME 默认正常，甚至不需要命令行 flags

### 4. fcitx5 协议层诊断

```bash
# 检查输入上下文状态
# focus:1 表示 IME 焦点激活，focus:0 表示未激活
fcitx5-diagnose 2>/dev/null | grep -A1 'program:APP_NAME'
```

**⚠️ 重要 pitfall**：`focus:0` 不一定表示修复失败。用户可能在你查 `fcitx5-diagnose` 时焦点在终端或其他窗口上，不在目标应用里。**必须在用户明确正在目标应用输入框中打字的同时查询**，才能得到准确的 focus 状态。用 `sleep N && fcitx5-diagnose | grep ...` 给用户切换窗口的时间。

## 修复方案（按推荐顺序）

### 方案 A：XDG desktop 文件覆盖（强制 Wayland + 补 feature flag）

创建 `~/.local/share/applications/<app>.desktop`，XDG 标准会自动覆盖系统级同名文件，launcher（noctalia、rofi、fuzzel 等）读取后使用新 Exec 行。

```ini
[Desktop Entry]
Name=AppName
Exec=/path/to/app --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3 %U
Terminal=false
Type=Application
# 其余字段从系统级 .desktop 复制
```

关键 flags 说明：
| Flag | 作用 |
|------|------|
| `--ozone-platform=wayland` | **强制** Wayland Ozone（不是 `hint=auto` 的自动检测） |
| `--enable-features=UseOzonePlatform` | 启用 Ozone 平台支持（Electron < 40 必需） |
| `--enable-features=WaylandWindowDecorations` | Wayland 原生窗口装饰 |
| `--enable-wayland-ime=true` | 启用 Wayland 输入法 |
| `--wayland-text-input-version=3` | 使用 text-input-v3 协议 |

**路径稳定性**：不用 nix store hash 路径（更新后失效），用 profile symlink（如 `~/.nix-profile/bin/qq`）或 `/run/current-system/profile/bin/`。

### 方案 B：XWayland 回退（只有当方案 A 不可行时）

```ini
Exec=/path/to/app --ozone-platform=x11 --enable-features=UseOzonePlatform %U
```

缺点：可能引入鼠标缩放问题（XWayland 无法正确继承 Wayland compositor 的 cursor size），且 XIM 路径可能有其他兼容性问题。

### 方案 C：使用系统 Electron 替换应用内置 Electron

```ini
Exec=env LD_PRELOAD=/path/to/libssh2.so /path/to/system/electron /path/to/app/resources/app %U
```

高风险：应用的原生 Node 模块可能与新 Electron 版本的 V8 不兼容，导致启动失败。仅当方案 A 不可行时尝试。

## 持久化

XDG desktop 文件覆盖是用户级配置，不需要修改系统包。但如果是 Guix/Nix 管理的系统，建议最终将 override 集成到 `source/config.org` 的包定义中，使修复在所有用户和所有启动方式下生效。

## 参考命令速查

```bash
# 查进程树和父进程链
ps -o pid,ppid,cmd -p $PID

# 查进程完整环境（所有变量）
cat /proc/$PID/environ | tr '\0' '\n' | sort

# 查 Wayland 库加载
cat /proc/$PID/maps | grep -i wayland

# 查 Electron 二进制文件
readlink -f /proc/$PID/exe

# 找系统级 .desktop
find /nix/store /run/current-system -path '*/share/applications/*<name>*' -name '*.desktop' 2>/dev/null
```
