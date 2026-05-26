<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

# Pi Agent 系统配置

本目录通过 `maak home` 的 stow 链接到 `~/.config/` 和 `~/.local/`。
⚠️ **Pi Agent 配置层已迁移至 `dotfiles/mutable/pi/.config/pi/`，详见下方目录结构说明。**

## 概述

当前目录承载两套 Agent 系统：

- **Pi Agent**（XDG 分层）— 基于 `badlogic/pi-mono` 的自定义 Agent 框架
  - 配置层 `~/.config/pi/` → 源文件位于 **`dotfiles/mutable/pi/.config/pi/`**（settings.json、agents、extensions、prompts 等）
  - 数据层 `~/.local/share/pi/`：package.json、node_modules、npm、sessions 等（运行时生成，不纳入版本控制）
- **全局上下文**（`~/.config/agents/context/`）— 被 OpenCode / Crush / Pi 共同引用的统一指引
- **Skills 体系**（`~/.config/agents/skills/`）— kb-curator、knowledge-base、self-improving、pack-guix

## 目录结构

```
agents/
├── .config/
│   ├── agents/
│   │   ├── context/         # 01-language.md, 02-ultilities.md（全局指令）
│   │   └── skills/          # kb-curator, knowledge-base, self-improving, pack-guix
│   ├── crush/               # Crush superpowers 配置（bin/、hooks/、crush.json）
│   └── opencode/            # OpenCode 配置（opencode.json、scripts/）
│
└── .local/
    ├── bin/                 # kb、pi、pi-acp、pi-update 入口脚本
    └── share/pi/            # Pi Agent 数据层（package.json、scripts、npm）
```

## 关键约定

- **加载顺序**：`01-language.md` → `02-ultilities.md`（AI 助手在最外层 AGENTS.md 中可同步注入）
- **Skills 引用**：`~/.config/agents/skills/` 中的 SKILL.md 被各类 Agent 引用

## 修改约束

- 修改全局上下文文件（`01-language.md`、`02-ultilities.md`）时，需同步影响所有引用方
- 新增 skill 时，先在既有 kb-curator/knowledge-base/self-improving 的 SKILL.md 中看模式
- `~/.local/bin/` 下的入口脚本是 stow 链接目标，不要直接编辑——改 `dotfiles/immutable/agents/.local/bin/` 中的源文件
