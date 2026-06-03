# Mutable Dotfiles（GNU Stow 管理）

本目录包含通过 GNU Stow 链接到 `$HOME` 的可变配置。

## 结构

```
mutable/
├── emacs/     # ★ Emacs 配置（Git 子模块 → codeberg.org/BrokenShine/.emacs.d）
│   └── .config/emacs/
│       ├── AGENTS.md        # Emacs 配置指引（含知识库体系）
│       ├── init.el
│       ├── early-init.el
│       ├── core/            # 路径常量、基础工具
│       ├── diagnose/        # 诊断框架与 ERT 测试
│       ├── configs/         # 系统/UI/编辑/编程/Org 模块
│       └── ...
├── pi/        # ★ Pi Agent 配置（settings.json、agents、extensions、prompts）
│   └── .config/pi/
│       ├── AGENTS.md        # Pi Agent 配置指引
│       ├── settings.json    # 核心配置
│       ├── agents/          # Subagent 定义
│       ├── extensions/      # 本地扩展
│       ├── prompts/         # Prompt 模板
│       └── ...
└── ssh/       # SSH 配置
```

## 部署机制

- `maak home` 调用 `stow-dotfiles` 函数，将子目录用 GNU Stow 链接到 `$HOME`
- 可直接编辑后运行 `maak home` 重新链接
- 也可在子目录内直接调试，Stow 链接会实时生效

## 核心子系统

### Pi Agent

- 基于 `pi-mono` 的自定义 Agent 框架
- 详见 `dotfiles/mutable/pi/AGENTS.md`
- `settings.json` 是核心配置：模型路由、子 agent、扩展包
- 配置源文件位于 `dotfiles/mutable/pi/.config/pi/`，通过 stow 链接到 `~/.config/pi/`

### Emacs

- 详见 `dotfiles/mutable/emacs/.config/emacs/AGENTS.md`
- 内建知识库体系（knowledge-base / kb-curator / self-improving）
- 新包需同步修改 `source/configs/home-config.org` 的包清单
- 禁止使用 `package.el`，所有包由 Guix 管理

## 修改约束

- Emacs 子模块修改需单独 commit 并 push 到 codeberg
- SSH 配置涉及安全，修改后需测试连接
