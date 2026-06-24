# dotfiles 总览

本目录包含用户级配置文件，统一通过 Guix Home 的 `home-dotfiles-service-type`（`stow` layout）部署到 `$HOME`。配置文件来源见 `source/config.org` 的 `dotfile-services` 代码块。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
dotfiles/
├── disable/
│   ├── dms-suite/
│   │   ├── .config/
│   │   │   ├── darkman/
│   │   │   ├── foot/
│   │   │   └── niri/
│   │   └── .local/
│   │       └── share/
│   └── waybar-suite/
│       ├── .config/
│       │   ├── darkman/
│       │   ├── foot/
│       │   ├── fuzzel/
│       │   ├── mako/
│       │   ├── niri/
│       │   ├── swayidle/
│       │   ├── swaylock/
│       │   └── waybar/
│       └── .local/
│           └── share/
└── enable/
    ├── agents/
    │   ├── .config/
    │   │   ├── agents/
    │   │   ├── crush/
    │   │   └── loopctl/
    │   ├── .local/
    │   │   └── bin/
    │   └── .gitignore
    ├── desktop/
    │   ├── .config/
    │   │   ├── autostart/
    │   │   ├── niri/
    │   │   ├── pcmanfm-qt/
    │   │   ├── rofi/
    │   │   ├── xdg-desktop-portal/
    │   │   └── xfce4/
    │   └── .local/
    │       ├── bin/
    │       └── share/
    ├── noctalia-suite/
    │   ├── .config/
    │   │   ├── darkman/
    │   │   └── niri/
    │   └── .local/
    │       └── share/
    ├── system/
    │   └── .config/
    │       ├── containers/
    │       ├── pipewire/
    │       ├── user-dirs.dirs
    │       └── user-dirs.locale
    ├── terminal/
    │   ├── .config/
    │   │   ├── atuin/
    │   │   ├── broot/
    │   │   ├── btop/
    │   │   ├── fastfetch/
    │   │   ├── fish/
    │   │   ├── foot/
    │   │   ├── tmux/
    │   │   ├── tmuxifier/
    │   │   └── starship.toml
    │   └── .local/
    │       └── bin/
    └── utilities/
        ├── .config/
        │   ├── fcitx5/
        │   ├── git/
        │   ├── helix/
        │   ├── kanata/
        │   ├── pnpm/
        │   └── winapps/
        ├── .local/
        │   ├── bin/
        │   └── share/
        └── .nix-channels
```

<!-- /structor -->

## 部署机制

- 入口：Guix Home `home-dotfiles-service-type`，在 `source/config.org` 的 `dotfile-services` 块声明
- `directories`：`'("../dotfiles/enable")`
- `layout`：`'stow`（自动以目录名为前缀建立软链接）
- `packages`：`agents desktop emacs noctalia-suite system terminal utilities`
- `excluded`：被排除的文件（`.git`、`.gitignore`、`AGENTS.md`、`README.md`、`__pycache__`、`.venv` 等）
- 新增子目录或新增子目录中文件：直接 `blue rebuild`；新文件若需排除请更新 `excluded` 正则

## 核心子系统

### Emacs（已迁移到 `stow/emacs/`）

- Emacs 配置已从 `dotfiles/enable/` 迁移到 `stow/`，通过 GNU Stow 直链部署（改源即生效）
- 详见 `stow/emacs/.config/emacs/AGENTS.md`
- Guix 通过 `(package (specification->package "emacs-nox"))` 等依赖提供 Emacs Lisp 包；新增包必须同步到 `source/config.org` 的 home-packages 清单
- **不要直接编辑子模块内容**

### oh-my-pi + Crush + loopctl（`enable/agents/`）

- **oh-my-pi (OMP)**：Guix 频道 `jeans` 的 `oh-my-pi-bin`（单 ELF 二进制），由 `source/config.org` 的 `home-packages` 提供；运行时配置走 `~/.config/pi/omp/`（约定路径由 `$PI_CONFIG_DIR` env 注入）。**本仓库不托管 OMP 配置源**。
- `.config/crush/`：Crush 配置（crush.json、hooks、bin）
- `.config/agents/`：共享 agent 基础设施（`context/`、`mcp-servers/kb-mcp/`、`skills/`）
- `.config/loopctl/`：跨 agent 长期循环框架（loopctl），adapter 内置 `claude-code` / `codex` / `crush` / **omp** / `opencode`
- `.local/bin/`：启动脚本（`kb`、`loopctl` 等）
- 详见 `dotfiles/enable/agents/AGENTS.md`

### Rime 输入法（`enable/utilities/.local/share/fcitx5/rime/`）

- Git 子模块（`github.com/iDvel/rime-ice`）
- 包含双拼、词典、Lua 扩展；**不要直接编辑子模块内容**

## 各子目录指引

| 子目录                   | 局部 AGENTS.md      | 主要职责                                           |
| ------------------------ | ------------------- | -------------------------------------------------- |
| `enable/agents/`         | ✅ 已有             | OMP、Crush、KB、loopctl、共享 skills、知识库       |
| `enable/desktop/`        | ✅ 已有             | niri、autostart、xdg-portal、xfce4 helpers         |
| `enable/noctalia-suite/` | ✅ 已有             | darkman、noctalia相关适配工作                      |
| `enable/system/`         | ✅ 已有             | containers、pipewire、xdg user-dirs                |
| `enable/terminal/`       | ✅ 已有             | fish、tmux、foot、btop、starship、broot、fastfetch |
| `enable/utilities/`      | ✅ 已有             | helix、git、kanata、pnpm、winapps、rime、gnupg     |
| `enable/emacs/`          | ✅ 已有（子模块内） | Emacs                                              |
