# dotfiles 总览

本目录包含用户级配置文件，统一通过 Guix Home 的 `home-dotfiles-service-type`（`stow` layout）部署到 `$HOME`。配置文件来源见 `source/config.org` 的 `dotfile-services` 代码块。

## 目录结构

<!-- structor:begin -->

<!-- 此结构图由 maak structor 自动维护，请勿手改 -->

```
dotfiles/
├── disable/
│   └── noctalia/
│       ├── .config/
│       │   ├── darkman/
│       │   ├── niri/
│       │   └── noctalia/
│       └── .local/
│           └── share/
└── enable/
    ├── agents/
    │   ├── .config/
    │   │   ├── agents/
    │   │   ├── crush/
    │   │   ├── loopctl/
    │   │   └── pi/
    │   ├── .local/
    │   │   ├── bin/
    │   │   └── share/
    │   └── .gitignore
    ├── desktop/
    │   └── .config/
    │       ├── autostart/
    │       ├── niri/
    │       ├── pcmanfm-qt/
    │       ├── xdg-desktop-portal/
    │       └── xfce4/
    ├── desktop-suite/
    │   ├── .config/
    │   │   ├── darkman/
    │   │   ├── foot/
    │   │   ├── fuzzel/
    │   │   ├── mako/
    │   │   ├── niri/
    │   │   ├── swayidle/
    │   │   ├── swaylock/
    │   │   └── waybar/
    │   └── .local/
    │       └── share/
    ├── emacs/
    │   └── .config/
    │       └── emacs/
    ├── system/
    │   └── .config/
    │       ├── containers/
    │       ├── pipewire/
    │       ├── user-dirs.dirs
    │       └── user-dirs.locale
    ├── terminal/
    │   ├── .config/
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
- `packages`：`agents desktop desktop-suite emacs system terminal utilities`
- `excluded`：被排除的文件（`.git`、`.gitignore`、`AGENTS.md`、`README.md`、`__pycache__`、`.venv` 等）
- 新增子目录或新增子目录中文件：直接 `maak rebuild`；新文件若需排除请更新 `excluded` 正则

## 核心子系统

### Emacs（`enable/emacs/`）

- 独立 git 子模块，实际代码在 `codeberg.org/BrokenShine/.emacs.d`
- 详见 `dotfiles/enable/emacs/.config/emacs/AGENTS.md`
- Guix 通过 `(package (specification->package "emacs-nox"))` 等依赖提供 Emacs Lisp 包；新增包必须同步到 `source/config.org` 的 home-packages 清单
- **不要直接编辑子模块内容**

### Pi Agent + Crush + loopctl（`enable/agents/`）

- `.config/pi/`：Pi Agent 的 agents/、extensions/、prompts/、settings.json、mcp.json、models.json 等
- `.config/crush/`：Crush 配置（crush.json、hooks、bin）
- `.config/agents/`：共享 agent 基础设施（`context/`、`mcp-servers/kb-mcp/`、`skills/`、`skillsets/`）
- `.config/loopctl/`：跨 agent 长期循环框架（loopctl）
- `.local/bin/`：启动脚本（`pi`、`pi-acp`、`pi-update`、`kb`、`loopctl` 等）
- 详见 `dotfiles/enable/agents/AGENTS.md`

### Rime 输入法（`enable/utilities/.local/share/fcitx5/rime/`）

- Git 子模块（`github.com/iDvel/rime-ice`）
- 包含双拼、词典、Lua 扩展；**不要直接编辑子模块内容**

## 各子目录指引

| 子目录                     | 局部 AGENTS.md | 主要职责                                                 |
| -------------------------- | -------------- | -------------------------------------------------------- |
| `enable/agents/`           | ✅ 已有        | Pi、Crush、KB、loopctl、共享 skills                      |
| `enable/desktop/`          | ✅ 已有        | niri、autostart、xdg-portal、xfce4 helpers              |
| `enable/desktop-suite/`    | ✅ 已有        | darkman、waybar、fuzzel、mako、foot themes、swayidle/lock |
| `enable/system/`           | ✅ 已有        | containers、pipewire、xdg user-dirs                      |
| `enable/terminal/`         | ✅ 已有        | fish、tmux、foot、btop、starship、broot、fastfetch       |
| `enable/utilities/`        | ✅ 已有        | helix、git、kanata、pnpm、winapps、rime、gnupg、bin      |
| `enable/emacs/`            | ✅ 已有（子模块内） | Emacs + 知识库（独立子模块）                        |