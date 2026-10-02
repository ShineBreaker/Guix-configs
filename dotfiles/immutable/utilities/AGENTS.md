# 开发工具与实用程序配置

本目录部署到 `~/.config/` 与 `~/.local/`，覆盖 Fcitx5/Rime 输入法、Helix、Git、Pnpm、GnuPG 与 WinApps。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
utilities/
├── .config/
│   ├── fcitx5/
│   ├── git/
│   ├── helix/
│   ├── npm/
│   ├── pnpm/
│   └── winapps/
└── .local/
    ├── bin/
    ├── share/
    └── state/
```

<!-- /structor -->

## 关键约定

- **Fcitx5 行为按 conf 文件分**：`conf/classicui.conf` 管候选窗外观（Material-Color-Teal 主题、`UseDarkTheme=True` 暗色跟随、`PerScreenDPI=False`），其余子系统各占 `conf/` 下一个文件，输入法集在 `profile/`。
- **Rime 方案与词库是子模块**：`.local/share/fcitx5/rime/` 指向 rime-ice（`.gitmodules` 中登记为 `rime`）。不要直接改子模块内的非自定义文件；更新在子模块内 pull，再提交主仓的 gitlink 引用。
- **Helix**：`languages.toml` 配各语言的 LSP 与 formatter，`themes/transparent.toml` 为透明背景主题。
- **Git**：`~/.config/git/gitmessage` 是全局 commit message 规范模板（仓库根 `AGENTS.md` 的提交规范以它为准）。
- **WinApps**：改 `winapps.conf` 或 `compose.yaml` 后需重新初始化对应 Windows 虚拟机。
- **Tab 补全联动**：在 `.local/bin/` 新增 CLI 脚本时，须同步在 `dotfiles/immutable/terminal/.config/fish/completions/<name>.fish` 添加补全。

## 修改与生效

- **通用**：改源后须 `blue home` 重建（部署进 Store 只读副本），不需要 `blue rebuild`。
- **其余随进程启动读取**：配置由进程启动时载入，改动需重启对应程序。
