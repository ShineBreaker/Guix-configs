# dotfiles 总览

本目录是用户级配置源，按变动频率分两套互补的部署模型。**`immutable/`（只读固化）**经 Guix Home 的 `home-dotfiles-service-type`（`layout 'stow`）部署，构建时复制进 `/gnu/store` 只读副本再软链到 `$HOME`，改源后必须 `blue home` 重建才生效；入口声明在 `source/config.org` 的 `dotfile-services` 块（`directories`/`packages`/`excluded`）。**`mutable/`（即时直链）**经 GNU Stow 直链仓库源码，改源即时生效，承载高频变动的应用配置（Emacs、Agenote、DSH、Hermes、Pi、Toolbox 等），详见 [mutable/AGENTS.md](mutable/AGENTS.md)。

子模块清单以 `.gitmodules` 为准，请勿直接编辑子模块内部文件（用户明确点名时除外）。

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
    └── tools/
```

<!-- /structor -->

## 子目录指引

| 子目录                      | AGENTS.md | 主要职责                                                                    |
| --------------------------- | --------- | --------------------------------------------------------------------------- |
| `immutable/agents/`         | 有        | 跨 Agent 共享基础设施：Context 上下文注入、Anchors 工具调用拦截             |
| `immutable/desktop/`        | 有        | 桌面环境：Niri、autostart、xdg-desktop-portal、PCManFM、Rofi、XFCE 辅助配置 |
| `immutable/noctalia-suite/` | 无        | 主题与外观适配（Darkman、Noctalia）                                         |
| `immutable/system/`         | 有        | 系统级用户态配置：容器策略、mihomo 代理、PipeWire 音频、XDG 用户目录        |
| `immutable/terminal/`       | 有        | 终端工具链：Fish、Tmux、Foot、Kitty、Starship、Btop、Atuin 等               |
| `immutable/utilities/`      | 有        | 常用工具与开发环境：Fcitx5/Rime、Helix、Git、Pnpm、GnuPG、WinApps           |
| `mutable/`                  | 有        | Emacs、Agenote、DSH、Hermes、Pi、Secrets、Toolbox 等可变配置包              |
