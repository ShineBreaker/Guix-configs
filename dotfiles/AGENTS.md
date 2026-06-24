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
│   │   │   │   ├── config/
│   │   │   │   │   ├── Kvantum/
│   │   │   │   │   ├── gtk-3.0/
│   │   │   │   │   ├── gtk-4.0/
│   │   │   │   │   ├── kitty/
│   │   │   │   │   ├── qt5ct/
│   │   │   │   │   ├── qt6ct/
│   │   │   │   │   └── .gtkrc-2.0
│   │   │   │   └── script/
│   │   │   │       ├── config.json
│   │   │   │       └── set-theme.sh
│   │   │   ├── foot/
│   │   │   │   └── themes/
│   │   │   │       └── material.ini
│   │   │   └── niri/
│   │   │       └── settings/
│   │   │           ├── key-bindings-wm.kdl
│   │   │           └── special.kdl
│   │   └── .local/
│   │       └── share/
│   │           ├── dark-mode.d/
│   │           │   └── 0-apply-theme.sh
│   │           ├── icons/
│   │           │   └── default/
│   │           └── light-mode.d/
│   │               └── 0-apply-theme.sh
│   └── waybar-suite/
│       ├── .config/
│       │   ├── darkman/
│       │   │   ├── config/
│       │   │   │   ├── Kvantum/
│       │   │   │   ├── fuzzel/
│       │   │   │   ├── gtk-3.0/
│       │   │   │   ├── gtk-4.0/
│       │   │   │   ├── kitty/
│       │   │   │   ├── mako/
│       │   │   │   ├── qt5ct/
│       │   │   │   ├── qt6ct/
│       │   │   │   ├── waybar/
│       │   │   │   └── .gtkrc-2.0
│       │   │   └── script/
│       │   │       ├── config.json
│       │   │       └── set-theme.sh
│       │   ├── foot/
│       │   │   └── themes/
│       │   │       └── material.ini
│       │   ├── fuzzel/
│       │   │   └── fuzzel.ini
│       │   ├── mako/
│       │   │   └── config
│       │   ├── niri/
│       │   │   └── settings/
│       │   │       ├── key-bindings-wm.kdl
│       │   │       └── special.kdl
│       │   ├── swayidle/
│       │   │   └── config
│       │   ├── swaylock/
│       │   │   └── config
│       │   └── waybar/
│       │       ├── config.jsonc
│       │       └── style.css
│       └── .local/
│           └── share/
│               ├── dark-mode.d/
│               │   └── 0-apply-theme.sh
│               ├── icons/
│               │   └── default/
│               └── light-mode.d/
│                   └── 0-apply-theme.sh
└── enable/
    ├── agents/
    │   ├── .config/
    │   │   ├── agents/
    │   │   │   ├── context/
    │   │   │   │   ├── 01-language.md
    │   │   │   │   └── 02-ultilities.md
    │   │   │   └── skills/
    │   │   │       ├── emacs-config/
    │   │   │       ├── knowledge-base/
    │   │   │       └── pack-guix/
    │   │   ├── crush/
    │   │   │   ├── bin/
    │   │   │   │   ├── bash-language-server
    │   │   │   │   ├── context7-mcp
    │   │   │   │   ├── filesystem-mcp
    │   │   │   │   ├── mcp-server-memory
    │   │   │   │   ├── mcp-server-sequential-thinking
    │   │   │   │   ├── typescript-language-server
    │   │   │   │   ├── vscode-css-language-server
    │   │   │   │   ├── vscode-eslint-language-server
    │   │   │   │   ├── vscode-html-language-server
    │   │   │   │   ├── vscode-json-language-server
    │   │   │   │   └── vscode-markdown-language-server
    │   │   │   ├── hooks/
    │   │   │   │   ├── bash-gate.sh
    │   │   │   │   └── edit-gate.sh
    │   │   │   └── crush.json
    │   │   └── loopctl/
    │   │       ├── adapters/
    │   │       │   ├── README.md
    │   │       │   ├── _TEMPLATE.json
    │   │       │   ├── claude-code.json
    │   │       │   ├── codex.json
    │   │       │   ├── crush.json
    │   │       │   ├── omp.json
    │   │       │   └── opencode.json
    │   │       └── docs/
    │   │           ├── examples/
    │   │           ├── README.md
    │   │           ├── adapter.md
    │   │           └── extract.md
    │   ├── .local/
    │   │   └── bin/
    │   │       ├── kb_lib/
    │   │       │   ├── __pycache__/
    │   │       │   ├── viz/
    │   │       │   ├── __init__.py
    │   │       │   ├── cards.py
    │   │       │   ├── core.py
    │   │       │   └── lint.py
    │   │       ├── loop_lib/
    │   │       │   ├── extract/
    │   │       │   ├── templates/
    │   │       │   ├── tests/
    │   │       │   ├── adapter-cmds.sh
    │   │       │   ├── agent.sh
    │   │       │   ├── common.sh
    │   │       │   ├── log.sh
    │   │       │   ├── prompt.sh
    │   │       │   └── state.sh
    │   │       ├── kb
    │   │       └── loopctl
    │   └── .gitignore
    ├── desktop/
    │   ├── .config/
    │   │   ├── autostart/
    │   │   │   ├── kdeconnect-indicator.desktop
    │   │   │   └── net.opentabletdriver.OpenTabletDriver.desktop
    │   │   ├── niri/
    │   │   │   ├── settings/
    │   │   │   │   ├── key-bindings.kdl
    │   │   │   │   └── window-rules.kdl
    │   │   │   ├── app-switcher.json
    │   │   │   └── config.kdl
    │   │   ├── pcmanfm-qt/
    │   │   │   └── default/
    │   │   │       ├── recent-files.conf
    │   │   │       └── settings.conf
    │   │   ├── rofi/
    │   │   │   └── config.rasi
    │   │   ├── xdg-desktop-portal/
    │   │   │   └── portals.conf
    │   │   └── xfce4/
    │   │       └── helpers.rc
    │   └── .local/
    │       ├── bin/
    │       │   └── niri-app-switcher
    │       └── share/
    │           └── applications/
    ├── emacs/
    │   └── .config/
    │       └── emacs/
    │           ├── .crush/
    │           │   ├── crush-fetch-3361075340/
    │           │   ├── logs/
    │           │   ├── .gitignore
    │           │   ├── crush.db
    │           │   ├── crush.db-shm
    │           │   └── crush.db-wal
    │           ├── configs/
    │           │   ├── coding/
    │           │   ├── editor/
    │           │   ├── i18n/
    │           │   ├── org/
    │           │   ├── system/
    │           │   ├── tools/
    │           │   └── ui/
    │           ├── core/
    │           │   ├── bootstrap.el
    │           │   └── lib.el
    │           ├── diagnose/
    │           │   ├── diagnostic-advice.el
    │           │   ├── diagnostic-context.el
    │           │   ├── diagnostic-env.el
    │           │   ├── diagnostic-install.el
    │           │   ├── diagnostic-log.el
    │           │   ├── diagnostic-report.el
    │           │   ├── diagnostic-state.el
    │           │   ├── diagnostic.el
    │           │   ├── run-tests.el
    │           │   ├── test-config-loading.el
    │           │   ├── test-core-lib.el
    │           │   ├── test-diagnostic.el
    │           │   ├── test-org-folding.el
    │           │   ├── test-org-knowledge-viz.el
    │           │   └── test-support.el
    │           ├── snippets/
    │           ├── .codex
    │           ├── .gitignore
    │           ├── CLAUDE.md
    │           ├── LICENSE
    │           ├── README.org
    │           ├── early-init.el
    │           └── init.el
    ├── noctalia-suite/
    │   ├── .config/
    │   │   ├── darkman/
    │   │   │   ├── config/
    │   │   │   │   ├── gtk-3.0/
    │   │   │   │   ├── gtk-4.0/
    │   │   │   │   ├── qt5ct/
    │   │   │   │   ├── qt6ct/
    │   │   │   │   └── .gtkrc-2.0
    │   │   │   └── script/
    │   │   │       ├── config.json
    │   │   │       └── set-theme.sh
    │   │   └── niri/
    │   │       └── settings/
    │   │           ├── key-bindings-wm.kdl
    │   │           └── special.kdl
    │   └── .local/
    │       └── share/
    │           ├── dark-mode.d/
    │           │   └── 0-apply-theme.sh
    │           ├── icons/
    │           │   └── default/
    │           └── light-mode.d/
    │               └── 0-apply-theme.sh
    ├── system/
    │   └── .config/
    │       ├── containers/
    │       │   ├── containers.conf
    │       │   └── policy.json
    │       ├── pipewire/
    │       │   └── pipewire.conf.d/
    │       │       └── 10-latency-fix.conf
    │       ├── user-dirs.dirs
    │       └── user-dirs.locale
    ├── terminal/
    │   ├── .config/
    │   │   ├── atuin/
    │   │   │   └── config.toml
    │   │   ├── broot/
    │   │   │   ├── conf.hjson
    │   │   │   └── verbs.hjson
    │   │   ├── btop/
    │   │   │   └── btop.conf
    │   │   ├── fastfetch/
    │   │   │   └── config.jsonc
    │   │   ├── fish/
    │   │   │   ├── conf.d/
    │   │   │   │   ├── 00-load-functions.fish
    │   │   │   │   ├── 01-guix.fish
    │   │   │   │   ├── 05-java.fish
    │   │   │   │   ├── 05-path.fish
    │   │   │   │   ├── 10-settings.fish
    │   │   │   │   ├── 20-greeting.fish
    │   │   │   │   ├── 99-command-not-found.fish
    │   │   │   │   └── 99-tmux.fish
    │   │   │   └── functions/
    │   │   │       ├── denv.fish
    │   │   │       ├── fish_prompt.fish
    │   │   │       ├── java_tools.fish
    │   │   │       └── retry.fish
    │   │   ├── foot/
    │   │   │   └── foot.ini
    │   │   ├── tmux/
    │   │   │   ├── scripts/
    │   │   │   │   ├── session-selector
    │   │   │   │   ├── sidebar-render.scm
    │   │   │   │   ├── sidebar-toggle
    │   │   │   │   ├── tmux-helpers.scm
    │   │   │   │   ├── which-key
    │   │   │   │   └── window-jump
    │   │   │   └── tmux.conf
    │   │   ├── tmuxifier/
    │   │   │   └── layouts/
    │   │   │       └── termide.session.sh
    │   │   └── starship.toml
    │   └── .local/
    │       └── bin/
    │           └── termide
    └── utilities/
        ├── .config/
        │   ├── fcitx5/
        │   │   ├── conf/
        │   │   │   ├── classicui.conf
        │   │   │   ├── keyboard.conf
        │   │   │   ├── notifications.conf
        │   │   │   ├── rime.conf
        │   │   │   └── waylandim.conf
        │   │   ├── config
        │   │   └── profile
        │   ├── git/
        │   │   ├── config
        │   │   └── gitmessage
        │   ├── helix/
        │   │   ├── themes/
        │   │   │   └── transparent.toml
        │   │   ├── config.toml
        │   │   └── languages.toml
        │   ├── kanata/
        │   │   └── kanata.kbd
        │   ├── pnpm/
        │   │   └── rc
        │   └── winapps/
        │       ├── compose.yaml
        │       └── winapps.conf
        ├── .local/
        │   ├── bin/
        │   │   ├── keepassxc-credential-setup
        │   │   ├── nixgpu-update
        │   │   ├── opencode-update
        │   │   └── xdg-bwrap
        │   └── share/
        │       ├── fcitx5/
        │       │   └── rime/
        │       └── gnupg/
        │           └── gpg-agent.conf
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
