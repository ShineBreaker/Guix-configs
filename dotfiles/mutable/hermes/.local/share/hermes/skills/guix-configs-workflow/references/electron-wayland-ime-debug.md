# Electron Wayland IME 调试完整流程

> 本文件记录 2026-06-22 会话中 QQ IME 不工作的完整调试过程。适用于任何 Electron 应用在 Wayland + fcitx5 + niri 下输入法失效的场景。

## 快速诊断命令

```bash
# 1. 环境变量完整性
cat /proc/$(pgrep -f '<app>' | head -1)/environ | tr '\0' '\n' | grep -E 'NIXOS_OZONE|GTK_IM|QT_IM|XMODIFIERS|SDL_IM|GLFW_IM|WAYLAND_DISPLAY' | sort

# 2. cmdline flag（关键：有没有 --ozone-platform=wayland + UseOzonePlatform）
cat /proc/$(pgrep -f '<app>' | head -1)/cmdline | tr '\0' ' '

# 3. Electron 版本（最准从 crashpad handler 拿）
ps aux | grep -i '<app>' | grep 'ver='
# 或从二进制
strings $(readlink -f /proc/$(pgrep -f '<app>' | head -1)/exe) | grep -oP '(Chrome|Electron)/\d+' | head -5

# 4. fcitx5 focus 状态
fcitx5-diagnose 2>/dev/null | grep -A1 'program:<app>'
# focus:0 = 协议未激活；focus:1 = 正常
```

## QQ 案例复盘

### 环境

- **Compositor**: niri 26.04（wlroots）
- **IME**: fcitx5 5.1.19（wayland_v2 frontend）
- **QQ**: 3.2.29（内嵌 Electron 37.1.0，Chromium ~130）
- **Hermes**: Electron 41.7.2（Chromium ~134）—— **工作正常，作对照**

### 调试步骤

1. **对比两端 /proc/PID/environ**：`comm -23 /tmp/env-hermes.txt /tmp/env-qq.txt` → 发现 IME 变量相同（NIXOS_OZONE_WL=1、GTK_IM_MODULE=fcitx 等），环境变量不是根因。

2. **对比 cmdline**：Hermes cmdline 零 flag；QQ 有 `--ozone-platform-hint=auto --enable-wayland-ime=true --wayland-text-input-version=3` —— flag 看似齐全。

3. **查 Electron 版本**：从 QQ 的 `chrome_crashpad_handler` 进程 cmdline 中提取 `--annotation=ver=37.1.0`；Hermes 是 41.7.2。

4. **查 fcitx5 IC**：`program:QQ frontend:wayland_v2 cap:72 focus:0` —— wayland 连接正常、capability 正常，但 focus 从未变成 1（即使点击输入框）。

5. **hypothesis**：QQ wrapper 的 `--ozone-platform-hint=auto` 在 Electron 37 上无法激活 text-input-v3 focus。Hermes（Electron 41）不需要任何 flag 就能工作。

### 尝试的修复

| 尝试 | flag | 结果 |
|---|---|---|
| 原始 | `--ozone-platform-hint=auto` | focus:0 |
| 方案 A | 同上 + `.desktop` 覆盖补 `UseOzonePlatform` | focus:0（显示正常） |
| 方案 B | `--ozone-platform=x11` | focus:0 + 鼠标缩放异常 |
| 方案 A修正 | `--ozone-platform=wayland` + `UseOzonePlatform` | focus:1 |

### 根因

QQ wrapper 的 `NIXOS_OZONE_WL` 条件块只加 `--ozone-platform-hint=auto`，Electron 37 上 `auto` hint 无法激活 Wayland text-input-v3 协议。必须用 `--ozone-platform=wayland`（强制，非 hint）+ `UseOzonePlatform` feature。

QQ wrapper 的 Exec 行：
```bash
exec "qq" ${NIXOS_OZONE_WL:+${WAYLAND_DISPLAY:+--ozone-platform-hint=auto ...}} --enable-wayland-ime --wayland-text-input-version=3 "$@"
```

最终 cmdline（.desktop 覆盖后）：
```
--ozone-platform=wayland              ← 覆盖 wrapper 的 =auto
--enable-features=UseOzonePlatform,WaylandWindowDecorations
--enable-wayland-ime=true
--wayland-text-input-version=3
--ozone-platform-hint=auto            ← wrapper 条件块（被前面的 =wayland 覆盖）
```

### 最终修复

**Nix 层**（`source/nix/configuration/00-main/packages.nix`）：
```nix
(qq.override {
  commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
})
```

**Guix dotfiles 层**（兜底，`dotfiles/enable/desktop/.local/share/applications/qq.desktop`）：
```ini
Exec=/home/brokenshine/.nix-profile/bin/qq --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3 %U
```

## 通用修复范式

当三件套（niri environment + herd set-environment + dbus-update-activation-environment）已确认生效，但特定 Electron 应用仍 `focus:0`：

1. **查 Electron 版本**：< 37 → 加 `UseOzonePlatform`；37–40 → 加 `UseOzonePlatform` + `--ozone-platform=wayland`；41+ → 通常不需要
2. **查当前 cmdline**：看是否只有 `--ozone-platform-hint=auto`（不是 `=wayland`）
3. **修复优先级**：Nix `commandLineArgs` override > Nix `xdg.desktopEntries` > Guix dotfiles .desktop 覆盖

## Electron 版本 vs Chromium 版本快速对照

| Electron | Chromium | 发布日期 | Wayland IME 状态 |
|---|---|---|---|
| 41 | 134 | 2026 Q1 | 默认成熟，零 flag 可工作 |
| 37 | 130 | 2025 Q4 | 需 `--ozone-platform=wayland` + `UseOzonePlatform` |
| 29–32 | 122–126 | 2024–2025 | 需 `UseOzonePlatform` |
| < 28 | < 120 | 2024 前 | Wayland IME 实验性 |
