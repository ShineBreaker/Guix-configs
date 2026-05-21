<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
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
│   ├── opencode/            # OpenCode 配置（opencode.json、scripts/）
│   └── pi/                  # Pi Agent 配置层（源文件实际在 `../../mutable/pi/.config/pi/`）
│       ├── settings.json    # ★ 核心配置：模型、路由、子 agent、扩展
│       ├── agents/          # oracle/planner/reviewer/scout/worker/researcher
│       ├── prompts/         # implement/scout-and-plan/design-review-implement 等
│       ├── models.json      # 模型定义与参数
│       └── extensions/      # global-context/index.ts, tmux-subagents/index.ts
└── .local/
    ├── bin/                 # kb、pi、pi-acp、pi-update 入口脚本
    └── share/pi/            # Pi Agent 数据层（package.json、scripts、npm）
```

## 环境变量

| 变量                          | 值                           | 用途             |
| ----------------------------- | ---------------------------- | ---------------- |
| `PI_CODING_AGENT_DIR`         | `$XDG_CONFIG_HOME/pi`        | Agent 配置目录   |
| `PI_CODING_AGENT_SESSION_DIR` | `$XDG_DATA_HOME/pi/sessions` | Session 存储目录 |

### 关键配置项

- `compaction`: 启用，保留 16384 tokens，保留最近 20000 tokens
- `retry`: 最多 3 次重试，基础延迟 2s
- `subagents.parallel`: 最大 8 任务，并发 4
- `ralphLoop`: 启用，最大 20 次迭代
- `todoEnforcer`: 启用
- `globalContext.contextDir`: `/home/brokenshine/.config/agents/context`
- `globalContext.extraFiles`: `/home/brokenshine/Documents/Org/profile.org`

## 关键约定

- **加载顺序**：`01-language.md` → `02-ultilities.md`（AI 助手在最外层 AGENTS.md 中可同步注入）
- **Skills 引用**：`~/.config/agents/skills/` 中的 SKILL.md 被 OpenCode 的 `available_skills` 引用
- **Pi Agent** 的 Skills 由安装的 npm 包提供，位于 `~/.local/share/pi/node_modules/` 中
- **settings.json 是核心**：任何模型/路由/子 agent 的修改都在这里

## 修改约束

- 修改全局上下文文件（`01-language.md`、`02-ultilities.md`）时，需同步影响所有引用方
- Crush 配置（`.config/crush/`）由上层 `home-config.org` 管理，不要单独修改
- 新增 skill 时，先在既有 kb-curator/knowledge-base/self-improving 的 SKILL.md 中看模式
- `~/.local/bin/` 下的入口脚本是 stow 链接目标，不要直接编辑——改 `dotfiles/immutable/agents/.local/bin/` 中的源文件
- **Pi Agent 配置**（settings.json、agents、prompts、models.json、extensions）的源文件在 `dotfiles/mutable/pi/.config/pi/`，不要直接编辑 `~/.config/pi/` 下的链接目标
- **settings.json 修改后需重启 Pi Agent 会话才能生效**
