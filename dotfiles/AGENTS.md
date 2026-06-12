# Dotfiles 总览

本目录包含用户级配置文件，由 `maak apply`（`guix system reconfigure` 内嵌的 home-environment）统一部署。

## 两层结构

```
dotfiles/
├── enable/      # 当前启用的配置（包含 immutable + mutable 两类）
│   ├── agents/         # Pi/Crush/KB skills（OpenCode/Crush/Pi Agent 资产）
│   ├── desktop/        # niri WM、autostart、xdg-portal（Guix Home 管理，只读）
│   ├── desktop-suite/  # WM 主题套件：darkman、waybar、fuzzel、mako
│   ├── emacs/          # ★ Emacs 配置（独立 git 子模块 → codeberg.org/BrokenShine/.emacs.d）
│   ├── system/         # containers、pipewire、user-dirs
│   ├── terminal/       # fish、tmux、foot、btop、starship
│   └── utilities/      # helix、git、kanata、winapps、rime
└── disable/     # 已禁用的旧配置（nix、noctalia）
```

> **结构说明**：
> - 原来的 `immutable/` + `mutable/` 顶层分层已合并到 `enable/` 下，每个子目录内部按需用 Guix Home 或 Stow 部署
> - `enable/<dir>/` 中标注 **★** 的是 GNU Stow mutable（可独立调试），其余是 Guix Home immutable（只读）
> - 新增配置请放入 `enable/<dir>/` 下的对应子目录

## 核心子系统

### Emacs（enable/emacs/）

- 独立 git 子模块，实际代码在 `codeberg.org/BrokenShine/.emacs.d`
- 详见 `dotfiles/enable/emacs/.config/emacs/AGENTS.md`
- 内建知识库体系（`kb-mcp` 工具集 + kb-curator / self-improving skills）
- 新包需同步修改 `source/config.org` 的 home-packages 段

### Pi Agent（enable/agents/）

- 基于 `pi-mono` 的自定义 Agent 框架
- `settings.json` 是核心配置：模型路由、子 agent、扩展包
- 配置源文件位于 `dotfiles/enable/agents/.config/pi/`
- 详见 `dotfiles/enable/agents/AGENTS.md`（完整配置参考）

## 部署机制

- `enable/<dir>/` 下的**普通子目录**（agents、desktop、desktop-suite、system、terminal、utilities）：通过 Guix Home 的 `home-dotfiles-service-type` 管理，构建时复制到 store，只读
- `enable/<dir>/` 下的**星标子目录**（emacs、agents 等）：通过 GNU Stow 链接到 `$HOME`，可直接修改后运行 `maak apply` 重链
- `disable/`：不再启用的配置文件，保留供参考

> **关键变化**：`maak.scm` 中已无独立的 `stow-dotfiles` 函数——stow 集成现在由 Guix Home 在 `guix-home-service` 内部自动完成。

## 各子目录指引

| 子目录                 | 局部 AGENTS.md | 部署方式   | 职责                                       |
| ---------------------- | -------------- | ---------- | ------------------------------------------ |
| `enable/agents/`       | ✅ 已有        | Guix Home  | Pi/Crush/KB skills、OpenCode 资产         |
| `enable/desktop/`      | ✅ 已有        | Guix Home  | niri、autostart、portal                    |
| `enable/desktop-suite/`| ✅ 已有        | Guix Home  | darkman、waybar、fuzzel、mako              |
| `enable/system/`       | ✅ 已有        | Guix Home  | containers、pipewire                       |
| `enable/terminal/`     | ✅ 已有        | Guix Home  | fish、tmux、foot、btop、starship           |
| `enable/utilities/`    | ✅ 已有        | Guix Home  | helix、git、kanata、winapps、rime          |
| `enable/emacs/`        | ✅ 已有        | GNU Stow   | Emacs + 知识库（独立子模块）               |
