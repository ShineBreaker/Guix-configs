<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Dotfiles 总览

本目录包含三层配置，由 `maak home` 统一部署。

## 三层结构

```
dotfiles/
├── immutable/   # Guix Home 管理（只读，构建时复制到 store）
│   ├── agents/      # ★ OpenCode / Crush / KB skills（Pi Agent 配置已迁移至 mutable/pi/）
│   ├── desktop/     # niri WM、autostart、xdg-portal
│   ├── system/      # containers、pipewire、user-dirs
│   ├── terminal/    # fish、tmux、foot、btop、starship
│   ├── utilities/   # helix、git、kanata、winapps、rime
│   └── wm/          # darkman 明暗切换、waybar、fuzzel、mako
├── mutable/     # GNU Stow 管理（直接调试修改，maak home 时重链）
RV:│   ├── emacs/   # ★ Emacs 配置（子模块 → codeberg.org/BrokenShine/.emacs.d）
PW:│   ├── pi/      # ★ Pi Agent 配置（settings.json、agents、prompts、extensions）
TR:│   └── ssh/     # SSH 配置
└── disable/     # 已禁用的旧配置（nix、noctalia）
```

## 核心子系统

### Emacs（mutable/emacs/）

- 子模块，实际代码在 `codeberg.org/BrokenShine/.emacs.d`
- 详见 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`
- 内建知识库体系（knowledge-base / kb-curator / self-improving skills）
- 新包需同步修改 `source/configs/home-config.org` 的包清单

### Pi Agent（mutable/pi/）

- 基于 `pi-mono` 的自定义 Agent 框架
- `settings.json` 是核心配置：模型路由、子 agent、扩展包
- 配置源文件位于 `dotfiles/mutable/pi/.config/pi/`，通过 stow 链接到 `~/.config/pi/`
- 详见 `dotfiles/immutable/agents/AGENTS.md`（含环境变量与修改约束说明）

## 部署机制

- `immutable/`：通过 Guix Home 的 `home-dotfiles-service-type` 管理
- `mutable/`：通过 `maak home` 中的 `stow-dotfiles` 函数用 GNU Stow 链接到 `$HOME`
- `disable/`：不再启用的配置文件，保留供参考

## 各子目录指引

| 子目录                 | 局部 AGENTS.md | 职责                                       |
| ---------------------- | -------------- | ------------------------------------------ |
| `immutable/agents/`    | ✅ 已有        | OpenCode / Crush / KB skills               |
| `mutable/pi/`          | —              | Pi Agent（settings.json、agents、prompts） |
| `immutable/desktop/`   | 见下方         | niri、autostart、portal                    |
| `immutable/system/`    | 见下方         | containers、pipewire                       |
| `immutable/terminal/`  | 见下方         | fish、tmux、foot、btop                     |
| `immutable/utilities/` | 见下方         | helix、git、kanata、rime                   |
| `immutable/wm/`        | 见下方         | darkman、waybar、fuzzel、mako              |
| `mutable/emacs/`       | ✅ 已有        | Emacs + 知识库                             |
| `mutable/ssh/`         | —              | SSH 配置                                   |
