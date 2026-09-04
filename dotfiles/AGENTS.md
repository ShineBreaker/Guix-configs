# dotfiles 总览

本目录是用户级配置源，分两套互补部署模型：

- **`immutable/`**：Guix Home `home-dotfiles-service-type`（`layout 'stow`）部署，入口声明在 `source/config.org` 的 `dotfile-services` 块（`directories`/`packages`/`excluded`）。构建时复制进 `/gnu/store` 只读副本再软链到 `$HOME` —— **改源 ≠ 生效，必须 `blue home`**。新增子目录或文件直接 `blue rebuild`；新文件若需排除（`.git`、`AGENTS.md`、`__pycache__`、`.venv` 等）更新 `excluded` 正则
- **`mutable/`**：GNU Stow 直链仓库源，改源即生效，详见 [mutable/AGENTS.md](mutable/AGENTS.md)

子模块清单以 `.gitmodules` 为权威，**不要直接编辑子模块内容**。

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

| 子目录                      | AGENTS.md | 主要职责                                           |
| --------------------------- | --------- | -------------------------------------------------- |
| `immutable/agents/`         | ✅        | Crush、共享 anchors 基础设施（omp 在 `mutable/agents/omp/`） |
| `immutable/desktop/`        | ✅        | niri、autostart、xdg-portal、xfce4 helpers         |
| `immutable/noctalia-suite/` | ❌        | darkman、noctalia 适配                             |
| `immutable/system/`         | ✅        | containers、pipewire、xdg user-dirs                |
| `immutable/terminal/`       | ✅        | fish、tmux、foot、kitty、starship、btop、atuin     |
| `immutable/utilities/`      | ✅        | fcitx5、git、helix、kanata、pnpm、winapps；Rime 子模块在 `.local/share/fcitx5/rime/`；gnupg 在 `.local/share/gnupg/` |
