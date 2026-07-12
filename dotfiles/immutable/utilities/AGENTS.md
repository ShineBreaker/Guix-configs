# 开发工具配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖编辑器、键盘改键、包管理器、Windows 应用桥接、Rime 输入法、GnuPG 等。

> **修改入口**：所有 `utilities/.config/<app>/` 下的文件改完都必须跑 `blue home`（不需 `blue rebuild`），然后 grep `~/.config/<app>/` 确认软链接到 store 副本。**禁止**直接编辑 `~/.config/<app>/` 已部署位置（store 副本只读，下次 `blue home` 会被覆盖）。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
utilities/
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

## 核心子系统

> fcitx5 用户配置由 `home-dotfiles-service-type` stow 到 `~/.config/fcitx5/`。运行时产物 `cached_layouts`、`crash.log` 在 `excluded` 列表跳过。

### fcitx5 输入法框架

- 路径：`utilities/.config/fcitx5/`（7 个文件：顶层 `config` + `profile`，子目录 `conf/` 5 个 .conf）
- 与 `.local/share/fcitx5/rime/`（Rime 子模块）配套使用，**不要混**——`.config/fcitx5/` 是 fcitx5 行为，`.local/share/fcitx5/rime/` 是 Rime 引擎资产
- `classicui.conf` 关键字段 `ForceWaylandDPI` 在 XWayland 应用上避免候选词被缩成 1.0x（参见修改约束）
- 修改后跑 `blue home` 即可生效，**不**需要 `blue rebuild`

### Rime 输入法

- 路径：`utilities/.local/share/fcitx5/rime/`
- Git 子模块（`github.com/iDvel/rime-ice`）
- 包含双拼方案（flypy、mspy、sogou 等）、词典、Lua 扩展
- **不要直接编辑子模块内容**，除非是 `custom_phrase.txt` 等用户自定义文件
- 子模块更新：进入子模块目录，按上游流程 `git pull` 后在主仓 commit

### Helix 编辑器

- `languages.toml` 定义语言服务器和格式化器
- `themes/transparent.toml` 提供透明背景主题

### Kanata 键盘映射

- `kanata.kbd` 定义键盘层映射，用于改键/宏

### Nix 备份分支

- `source/nix/` 与 `.nix-channels` 构成独立 Nix home-manager 配置，与 Guix **不互通**
- 操作：`blue nix` / `blue nix-init` / `blue nix-update`

## 修改约束

- 改源后 `blue home` 即可生效（不需 `blue rebuild`）
- Rime 子模块修改需在子模块内 commit/push 到上游
- Git commit 模板：`~/.config/git/gitmessage`
- winapps 改后需重建 VM
