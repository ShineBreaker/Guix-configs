# 开发工具配置

通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`。涵盖编辑器、键盘改键、包管理器、Windows 应用桥接、Rime 输入法、GnuPG 等。

> **修改入口**：`utilities/.config/<app>/` 下文件改完必须 `blue home`（不需 `blue rebuild`），再 grep `~/.config/<app>/` 确认软链到 store 副本。**禁止**直接编辑已部署位置（store 副本只读，下次 `blue home` 会覆盖）。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
utilities/
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

## 核心子系统

> 运行时产物 `cached_layouts`、`crash.log` 已在 `excluded` 列表跳过。

### fcitx5 输入法框架

- 路径：`utilities/.config/fcitx5/`（顶层 `config` + `profile`，`conf/` 下 5 个 .conf），与 `.local/share/fcitx5/rime/`（Rime 子模块）分工：此处管 fcitx5 行为，彼处是 Rime 引擎资产，**不要混**
- `classicui.conf` 的 `ForceWaylandDPI` 避免 XWayland 应用候选词被缩成 1.0x

### Rime 输入法

- 路径：`utilities/.local/share/fcitx5/rime/`，Git 子模块（`github.com/iDvel/rime-ice`），含双拼方案（flypy、mspy、sogou 等）、词典、Lua 扩展；**不要直接编辑子模块内容**（`custom_phrase.txt` 等用户自定义文件除外）
- 更新：子模块内按上游流程 `git pull`，回主仓 commit

### Helix 编辑器

- `languages.toml` 定义语言服务器与格式化器；`themes/transparent.toml` 提供透明背景主题

### Kanata 键盘映射

- `kanata.kbd` 定义键盘层映射（改键/宏）

### Nix 备份分支

- `source/nix/` + `.nix-channels`：独立 Nix home-manager 配置，与 Guix **不互通**；操作：`blue nix`（经 `nh home switch`）/ `blue nix-init` / `blue update --nix`

## 修改约束

- 改源后 `blue home` 生效（不需 `blue rebuild`）
- Rime 子模块修改需在子模块内 commit/push 到上游
- Git commit 模板：`~/.config/git/gitmessage`
- winapps 改后需重建 VM
- **新增脚本必须同步补全**：`.local/bin/` 新增可执行（如 `keepassxc-credential-setup`、`nixgpu-update`）时，须同步在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 新增鱼壳 Tab 补全（`complete -c <name>`）
