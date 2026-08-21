# QQ + niri + Guix 输入法修复实录

## 问题

- QQ（Electron 37.1.0，内置在 nix store）从 noctalia-shell 桌面 launcher 启动后 fcitx5 输入法不可用
- 终端启动的 hermes-desktop（Electron 41.7.2）输入法正常
- 两个进程的 IME 环境变量（GTK_IM_MODULE、QT_IM_MODULE、XMODIFIERS、NIXOS_OZONE_WL 等）完全一致

## 诊断过程

1. 对比两个进程的 `/proc/PID/environ` —— IME 变量一致，排除环境变量问题
2. 对比 `/proc/PID/cmdline` —— hermes 零 flag 也能工作（Electron 41 默认好），QQ 有 `--ozone-platform-hint=auto` 但 focus 始终 0
3. 从 crashpad handler 确认 QQ Electron 版本：`--annotation=ver=37.1.0`
4. `fcitx5-diagnose` 显示 `program:QQ frontend:wayland_v2 cap:72 focus:0`，连接存在但 焦点无法激活

## 尝试过的方案

| 方案 | 结果 |
|------|------|
| `--ozone-platform=x11`（XWayland 回退）| ❌ 输入法仍不可用 + 鼠标缩放异常 |
| 系统 Electron 41 替换内置 Electron 37 | 未测试（原生模块兼容性风险） |
| `--ozone-platform=wayland --enable-features=UseOzonePlatform` | ✅ 输入法和显示均正常 |

## 最终 fix

`~/.local/share/applications/qq.desktop`：

```ini
[Desktop Entry]
Name=QQ
Exec=/home/brokenshine/.nix-profile/bin/qq --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime=true --wayland-text-input-version=3 %U
Terminal=false
Type=Application
Icon=/nix/store/d8d5ldmsl86piv3i6nv3nnzkf4zgxmf8-qq-3.2.29-2026-05-28/share/icons/hicolor/512x512/apps/qq.png
StartupWMClass=QQ
Categories=Network;
Comment=QQ
```

使用 `~/.nix-profile/bin/qq`（symlink）而非 nix store hash 路径，QQ 版本更新后自动跟进。

## QQ wrapper 的干扰

QQ 的 nix wrapper 脚本本身也会根据 `${NIXOS_OZONE_WL}` 条件添加 `--ozone-platform-hint=auto`。`.desktop` 的 flags 通过 `$@` 传入 wrapper 后追加到最终 cmdline，`--ozone-platform=wayland` 覆盖了 wrapper 添加的 `--ozone-platform-hint=auto`。

## 关键教训

- `fcitx5-diagnose` 的 `focus:0` 不一定表示修复失败——用户可能在那瞬间焦点在别的窗口
- Electron 版本差异是决定性因素：41 不需要任何 flag 就好，37 需要 `--ozone-platform=wayland` 强制 + `UseOzonePlatform`
- `--ozone-platform=wayland` 和 `--ozone-platform-hint=auto` 不是同一回事；`hint=auto` 在旧 Electron 上有 bug
