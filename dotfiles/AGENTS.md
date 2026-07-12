# dotfiles 总览

本目录包含用户级配置文件，统一通过 Guix Home 的 `home-dotfiles-service-type`（`stow` layout）部署到 `$HOME`。配置文件来源见 `source/config.org` 的 `dotfile-services` 代码块。

## 目录结构

<!-- structor:begin depth=4 -->

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
├── immutable/
│   ├── agents/
│   │   ├── .config/
│   │   │   ├── agents/
│   │   │   ├── crush/
│   │   │   ├── loopctl/
│   │   │   └── opencode/
│   │   ├── .local/
│   │   │   └── bin/
│   │   └── .gitignore
│   ├── desktop/
│   │   ├── .config/
│   │   │   ├── autostart/
│   │   │   ├── niri/
│   │   │   ├── pcmanfm-qt/
│   │   │   ├── rofi/
│   │   │   ├── xdg-desktop-portal/
│   │   │   └── xfce4/
│   │   └── .local/
│   │       └── bin/
│   ├── noctalia-suite/
│   │   ├── .config/
│   │   │   ├── darkman/
│   │   │   └── niri/
│   │   └── .local/
│   │       └── share/
│   ├── system/
│   │   └── .config/
│   │       ├── containers/
│   │       ├── pipewire/
│   │       ├── wireplumber/
│   │       ├── user-dirs.dirs
│   │       └── user-dirs.locale
│   ├── terminal/
│   │   ├── .config/
│   │   │   ├── atuin/
│   │   │   ├── broot/
│   │   │   ├── btop/
│   │   │   ├── fastfetch/
│   │   │   ├── fish/
│   │   │   ├── foot/
│   │   │   ├── tmux/
│   │   │   ├── tmuxifier/
│   │   │   └── starship.toml
│   │   └── .local/
│   │       └── bin/
│   └── utilities/
│       ├── .config/
│       │   ├── fcitx5/
│       │   ├── git/
│       │   ├── helix/
│       │   ├── kanata/
│       │   ├── pnpm/
│       │   └── winapps/
│       ├── .local/
│       │   ├── bin/
│       │   └── share/
│       └── .nix-channels
└── mutable/
    ├── agenote/
    │   ├── .config/
    │   │   └── agents/
    │   ├── .local/
    │   │   └── bin/
    │   ├── .stow-folding
    │   └── .stow-local-ignore
    ├── appimage-run/
    ├── emacs/
    │   ├── .config/
    │   │   ├── agents/
    │   │   └── emacs/
    │   └── .stow-local-ignore
    ├── hermes/
    │   ├── .local/
    │   │   └── share/
    │   └── .stow-folding
    ├── pi/
    │   ├── .config/
    │   │   └── pi/
    │   ├── .local/
    │   │   ├── bin/
    │   │   └── share/
    │   └── .stow-local-ignore
    ├── secrets/
    │   ├── .local/
    │   │   └── share/
    │   └── .stow-local-ignore
    └── skills/
        ├── .config/
        │   └── agents/
        └── .stow-folding
```

<!-- /structor -->

## 部署机制

- 入口：Guix Home `home-dotfiles-service-type`，在 `source/config.org` 的 `dotfile-services` 块声明
- `directories`：`'("../dotfiles/immutable")`
- `layout`：`'stow`（自动以目录名为前缀建立软链接）
- `packages`：`agents desktop noctalia-suite system terminal utilities`
- `excluded`：被排除的文件（`.git`、`.gitignore`、`AGENTS.md`、`README.md`、`__pycache__`、`.venv` 等）
- 新增子目录或新增子目录中文件：直接 `blue rebuild`；新文件若需排除请更新 `excluded` 正则

## 核心子系统

### Emacs（`dotfiles/mutable/emacs/`）

- Emacs 配置在 `dotfiles/mutable/emacs/`，通过 GNU Stow 直链部署，改源即生效
- Guix 提供 Emacs Lisp 包依赖；新增包必须同步到 `source/config.org` home-packages
- **不要直接编辑子模块内容**（详见 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`）

### oh-my-pi + Crush + loopctl（`immutable/agents/`）

- **OMP**：`jeans` 频道的 `oh-my-pi-bin`，`home-packages` 提供 `omp` 命令。**仓库不托管配置源**，本地维护 `~/.config/pi/omp/`
- **Crush**：`.config/crush/`（crush.json、hooks、bin）
- **loopctl**：`.config/loopctl/`（adapters 含 claude-code/codex/crush/omp/opencode/pi）
- **共享基础设施**：`.config/agents/`（context、skills）
- **启动脚本**：`.local/bin/`（kb、loopctl 等）
- 详见 `dotfiles/immutable/agents/AGENTS.md`

### Rime 输入法（`immutable/utilities/.local/share/fcitx5/rime/`）

- Git 子模块（`github.com/iDvel/rime-ice`）：双拼、词典、Lua 扩展
- **不要直接编辑子模块内容**（`custom_phrase.txt` 等用户自定义文件除外）

## 各子目录指引

| 子目录                      | AGENTS.md | 主要职责                                           |
| --------------------------- | --------- | -------------------------------------------------- |
| `immutable/agents/`         | ✅ 已有   | OMP、Crush、KB、loopctl、共享 skills、知识库       |
| `immutable/desktop/`        | ✅ 已有   | niri、autostart、xdg-portal、xfce4 helpers         |
| `immutable/noctalia-suite/` | ❌ 无     | darkman、noctalia 适配                             |
| `immutable/system/`         | ✅ 已有   | containers、pipewire、xdg user-dirs                |
| `immutable/terminal/`       | ✅ 已有   | fish、tmux、foot、btop、starship、broot、fastfetch |
| `immutable/utilities/`      | ✅ 已有   | helix、git、kanata、pnpm、winapps、rime、gnupg     |
