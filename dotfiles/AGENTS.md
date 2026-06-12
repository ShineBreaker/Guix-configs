# dotfiles 总览

本目录包含用户级配置文件，统一通过 Guix Home 的 `home-dotfiles-service-type`（`stow` layout）部署到 `$HOME`。配置文件来源见 `source/config.org` 的 `dotfile-services` 代码块。

## 目录结构

```
dotfiles/
├── enable/        # 当前启用的配置（maak rebuild 时统一部署）
│   ├── agents/         # Agent 资产（Pi、Crush、KB、loopctl、共享 skillsets）
│   ├── desktop/        # 桌面环境（niri、autostart、portal、xfce4 helpers）
│   ├── desktop-suite/  # WM 主题套件（darkman、waybar、fuzzel、mako、foot themes、swayidle/lock）
│   ├── emacs/          # Emacs 配置（独立 git 子模块）
│   ├── system/         # 系统级（containers、pipewire、xdg user-dirs）
│   ├── terminal/       # 终端工具链（fish、tmux、foot、btop、starship、broot、fastfetch）
│   └── utilities/      # 开发工具（helix、git、kanata、pnpm、winapps、rime、gnupg、bin）
└── disable/       # 已弃用的旧配置（noctalia 等），不再部署
```

> **结构说明**：
> - 旧的顶层 `immutable/` + `mutable/` 拆分已合并到 `enable/<app>/`，所有目录均通过 Guix Home stow 部署
> - 不存在 "mutable 子目录需要 `stow -R` 手动重链" 的概念；每次 `maak rebuild` 都重新链接
> - 新增配置请放入 `enable/<app>/` 的对应子目录，并在 `source/config.org` 的 `dotfile-services` 的 `packages` 列表中追加目录名
> - 详见各子目录 `AGENTS.md`

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