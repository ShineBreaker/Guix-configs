# dotfiles 总览

本目录是用户级配置源，按变动频率和管理方式分为两套互补的部署模型：

- **`immutable/`（只读固化）**：通过 Guix Home 的 `home-dotfiles-service-type`（`layout 'stow`）部署。构建时复制进 `/gnu/store` 只读副本并软链到 `$HOME`。**修改源码后必须运行 `blue home` 重建生效**。入口声明在 `source/config.org` 的 `dotfile-services` 块（`directories`/`packages`/`excluded`）。
- **`mutable/`（即时直链）**：通过 GNU Stow 直接软链仓库源码，**修改源码即时生效**，适合高频变动的应用配置（如 Emacs、Lem、Hermes 等）。详见 [mutable/AGENTS.md](mutable/AGENTS.md)。

> **提示**：子模块清单以 `.gitmodules` 为准，请勿直接编辑子模块内部文件。

## 目录结构

<!-- structor:begin depth=2 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
dotfiles/
├── immutable/
│   ├── agents/
│   ├── desktop/
│   ├── noctalia-suite/
│   ├── system/
│   ├── terminal/
│   └── utilities/
└── mutable/
    ├── agenote/
    ├── agents/
    ├── emacs/
    ├── lem/
    └── tools/
```

<!-- /structor -->

## 子目录指引

| 子目录                      | AGENTS.md | 主要职责                                                        |
| --------------------------- | --------- | --------------------------------------------------------------- |
| `immutable/agents/`         | ✅        | Crush 配置与跨 Agent 共享基础设施（context 注入、anchors 拦截） |
| `immutable/desktop/`        | ✅        | 桌面环境：Niri 窗口管理器、autostart、xdg-portal、XFCE 辅助配置 |
| `immutable/noctalia-suite/` | ❌        | 主题与外观适配（Darkman、Noctalia）                             |
| `immutable/system/`         | ✅        | 系统级用户态配置：容器策略、PipeWire 音频、XDG 用户目录         |
| `immutable/terminal/`       | ✅        | 终端工具链：Fish、Tmux、Foot、Kitty、Starship、Btop、Atuin 等   |
| `immutable/utilities/`      | ✅        | 常用工具与开发环境：Fcitx5、Git、Helix、Pnpm、WinApps、GnuPG 等 |
| `mutable/`                  | ✅        | 包含 Emacs、Lem、DSH、Hermes、Pi、Secrets、Toolbox 等可变配置包 |
