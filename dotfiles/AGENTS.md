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
│   │   │   └── loopctl/
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
│   │   └── .config/
│   │       ├── atuin/
│   │       ├── broot/
│   │       ├── btop/
│   │       ├── fastfetch/
│   │       ├── fish/
│   │       ├── foot/
│   │       ├── herdr/
│   │       └── starship.toml
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
    │   ├── .local/
    │   │   └── share/
    │   └── .stow-local-ignore
    ├── hermes/
    │   ├── .local/
    │   │   ├── bin/
    │   │   └── share/
    │   ├── .stow-folding
    │   └── .stow-local-ignore
    ├── omp/
    │   ├── .config/
    │   │   ├── agents/
    │   │   └── omp/
    │   ├── .gitignore
    │   ├── .stow-local-ignore
    │   ├── config.yml
    │   ├── global-context.json
    │   └── mcp.json
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

## 各子目录指引

| 子目录                      | AGENTS.md | 主要职责                                           |
| --------------------------- | --------- | -------------------------------------------------- |
| `immutable/agents/`         | ✅ 已有   | OMP、Crush、KB、loopctl、共享 skills、知识库       |
| `immutable/desktop/`        | ✅ 已有   | niri、autostart、xdg-portal、xfce4 helpers         |
| `immutable/noctalia-suite/` | ❌ 无     | darkman、noctalia 适配                             |
| `immutable/system/`         | ✅ 已有   | containers、pipewire、xdg user-dirs                |
| `immutable/terminal/`       | ✅ 已有   | fish、tmux、foot、btop、starship、broot、fastfetch |
| `immutable/utilities/`      | ✅ 已有   | helix、git、kanata、pnpm、winapps、rime、gnupg     |
