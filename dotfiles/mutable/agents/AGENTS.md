<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Agent 系统配置

本目录通过 `maak home` 的 stow 链接到 `~/.config/agents/` 和 `~/.local/share/pi/`。

## 概述

当前目录承载两套 Agent 系统：

- **Pi Agent**（`~/.local/share/pi/`）— 基于 `badlogic/pi-mono` 的自定义 Agent 框架，含扩展、Skills、Subagent
- **全局上下文**（`~/.config/agents/context/`）— 被 OpenCode / Crush / Pi 共同引用的统一指引

## 目录结构

    agents/
    ├── .config/
    │   ├── agents/context/    # 01-language.md, 02-ultilities.md（全局指令）
    │   ├── agents/skills/     # kb-curator, knowledge-base, self-improving
    │   └── crush/             # Crush superpowers 配置（bin/、hooks/、crush.json）
    └── .local/
        ├── bin/               # kb、pi 入口脚本
        └── share/pi/          # Pi Agent 完整配置（详见子目录 AGENTS.md）

## 关键约定

- **加载顺序**：`01-language.md` → `02-ultilities.md`（AI 助手在最外层 AGENTS.md 中可同步注入）
- **Skills 引用**：`~/.config/agents/skills/` 中的 SKILL.md 被 OpenCode 的 `available_skills` 引用
- **Pi Agent** 的 Skills 不放在本目录，而是独立置于 `~/.pi/agent/skills/`

## 修改约束

- 修改全局上下文文件（`01-language.md`、`02-ultilities.md`）时，需同步影响所有引用方
- Crush 配置（`.config/crush/`）由上层 `home-config.org` 管理，不要单独修改
- 新增 skill 时，先在既有 kb-curator/knowledge-base/self-improving 的 SKILL.md 中看模式
- `~/.local/bin/` 下的入口脚本是 stow 链接目标，不要直接编辑——改 `dotfiles/mutable/agents/.local/bin/` 中的源文件
