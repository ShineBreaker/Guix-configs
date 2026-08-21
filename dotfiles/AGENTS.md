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
│   │   │   └── crush/
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
│   │   ├── .config/
│   │   │   ├── containers/
│   │   │   ├── hypr/
│   │   │   ├── pipewire/
│   │   │   ├── wireplumber/
│   │   │   ├── user-dirs.dirs
│   │   │   └── user-dirs.locale
│   │   └── .local/
│   │       └── bin/
│   ├── terminal/
│   │   └── .config/
│   │       ├── atuin/
│   │       ├── broot/
│   │       ├── btop/
│   │       ├── fastfetch/
│   │       ├── fish/
│   │       ├── foot/
│   │       ├── herdr/
│   │       ├── kitty/
│   │       ├── tmux/
│   │       ├── tmuxifier/
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
    │   │   ├── agents/
    │   │   └── pi/
    │   ├── .zcode/
    │   │   └── plugins/
    │   └── .stow-local-ignore
    ├── agents/
    │   ├── hermes/
    │   │   ├── .local/
    │   │   ├── .stow-folding
    │   │   └── .stow-local-ignore
    │   ├── pi/
    │   │   ├── .config/
    │   │   └── .stow-local-ignore
    │   └── zcode/
    │       └── .zcode/
    ├── emacs/
    │   ├── .config/
    │   │   ├── agents/
    │   │   └── emacs/
    │   ├── .local/
    │   │   └── share/
    │   └── .stow-local-ignore
    └── tools/
        ├── appimage-run/
        └── secrets/
            ├── .local/
            └── .stow-local-ignore
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
| `immutable/agents/`         | ✅ 已有   | OMP、Crush、KB、共享 skills、知识库               |
| `immutable/desktop/`        | ✅ 已有   | niri、autostart、xdg-portal、xfce4 helpers         |
| `immutable/noctalia-suite/` | ❌ 无     | darkman、noctalia 适配                             |
| `immutable/system/`         | ✅ 已有   | containers、pipewire、xdg user-dirs                |
| `immutable/terminal/`       | ✅ 已有   | fish、tmux、foot、btop、starship、broot、fastfetch |
| `immutable/utilities/`      | ✅ 已有   | fcitx5、git、helix、kanata、pnpm、winapps；Rime 子模块在 `.local/share/fcitx5/rime/`；gnupg 在 `.local/share/gnupg/` |
