# 开发工具配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖编辑器、键盘改键、包管理器、Windows 应用桥接、Rime 输入法、GnuPG 等。

## 目录结构

```
utilities/.config/
├── git/
│   ├── config                           # Git 全局配置
│   └── gitmessage                       # Commit 消息模板
├── helix/
│   ├── config.toml
│   ├── languages.toml                   # LSP / formatter 定义
│   └── themes/
│       └── transparent.toml             # 透明主题
├── kanata/
│   └── kanata.kbd                       # 键盘层映射 / 改键宏
├── pnpm/
│   └── rc                               # pnpm 配置
└── winapps/
    ├── compose.yaml
    └── winapps.conf                     # Windows 应用集成

utilities/.local/
├── bin/
│   ├── keepassxc-credential-setup
│   ├── nixgpu-update
│   ├── opencode-update                  # OpenCode 更新脚本
│   └── xdg-bwrap
└── share/
    ├── fcitx5/
    │   └── rime/                        # ★ Rime 子模块（github.com/iDvel/rime-ice）
    └── gnupg/
        └── gpg-agent.conf

.nix-channels                            # Nix 频道声明（独立分支使用）
```

## 核心子系统

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

### Nix 备份分支（独立使用）

- 仓库根的 `source/nix/` 与本目录的 `.nix-channels` 共同构成一份独立的 Nix home-manager 配置
- 与 Guix 配置并存但**不互通**：走 `maak nix` / `maak nix-init` / `maak nix-update`
- 主要作用是给特定工具（Nix 生态）做隔离验证

## 修改约束

- 修改后必须 `maak rebuild` 才会生效
- Rime 子模块修改需在子模块内单独 commit 并 push 到上游
- Git commit 模板通过 `~/.config/git/gitmessage`（已通过 `git config commit.template` 引用）
- winapps 配置修改后需重建 VM