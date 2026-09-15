# 开发工具与实用程序配置

本目录通过 Guix Home 部署到 `~/.config/` 与 `~/.local/`，涵盖输入法（Fcitx5 / Rime）、轻量编辑器（Helix）、版本控制（Git）、包管理器（Pnpm）、Windows 应用桥接（WinApps）以及 GnuPG 等。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
utilities/
├── .config/
│   ├── fcitx5/
│   ├── git/
│   ├── helix/
│   ├── pnpm/
│   └── winapps/
└── .local/
    ├── bin/
    ├── share/
    └── state/
```

<!-- /structor -->

## 核心子系统与约定

### Fcitx5 输入法框架与 Rime

- **Fcitx5 配置**（`utilities/.config/fcitx5/`）：负责输入法前端框架行为。`conf/classicui.conf` 管理候选窗外观（Material-Color-Teal 主题、暗色跟随、`PerScreenDPI=False`）。
- **Rime 方案与词库**（`utilities/.local/share/fcitx5/rime/`）：通过 Git 子模块引入 `rime-ice`，包含双拼方案、拼音词库与 Lua 扩展。
  - 请勿直接在子模块内修改非自定义文件；词库与方案更新在子模块内 pull 并提交主仓引用。

### Helix 编辑器

- `languages.toml`：配置各语言的 LSP Language Server 与 Code Formatter。
- `themes/transparent.toml`：提供透明背景的编辑主题。

### Git 与辅助工具

- **Git 提交模板**：`~/.config/git/gitmessage` 作为全局 commit message 规范模板。
- **WinApps 桥接**：修改 WinApps 配置后需重新初始化对应 Windows 虚拟机。

## 修改与生效流程

1. **部署生效**：修改源码后执行 `blue home` 即可部署（无需 `blue rebuild`）。
2. **Tab 补全联动**：当在 `.local/bin/` 新增 CLI 脚本时，须同步在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 添加 Fish 补全。
