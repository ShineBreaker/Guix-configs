<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# 40-force-unmute — ALSA sink 就绪时强制取消 route 静音（兜底）

- 源码：`dotfiles/immutable/system/.config/wireplumber/scripts/40-alsa/40-force-unmute.lua`
- 部署：`~/.config/wireplumber/scripts/40-alsa/40-force-unmute.lua`（immutable，改后需 `blue home`）
- 调用方：WirePlumber 加载 `scripts/40-alsa/` 目录时自动注册

## 工作原理

监听 ALSA device 的 route 就绪事件，对 mute 状态的路由写 `Route` 参数 `mute = false`，再 `device:set_param("Route", …)` 应用。

## 设计决策与不变量

- **`save = false`**：只改运行时状态，不写回路由持久化——避免把兜底动作固化进用户配置。
- **目录名 `40-alsa`**：WirePlumber 按字典序加载脚本目录，`40-*` 先于上游 `50-alsa` 注册 hook，保证拦截时机。

## 变更记录

- 2026-09-29：头部注释精简（不变量保留在代码头，行为不变）。
