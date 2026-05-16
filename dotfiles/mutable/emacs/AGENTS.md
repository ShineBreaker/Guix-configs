<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# dotfiles/mutable/emacs

本目录是 Guix-configs 仓库中 Emacs 配置的 Stow 包装层。

```
.config/
├── emacs/       # Emacs 配置
├── agents/
│   └── skills/  # Agent Skill 定义（knowledge-base、kb-curator、self-improving 等）
└── …
.local/bin/
└── kb           # 知识库 CLI 工具
```

skills 和 CLI 工具构成一个以 Emacs Org-mode 为核心的 **知识库体系**， 三个组成部分一体联动：
- **Emacs Org-mode** 是知识创作与组织的前端
- **agent skills** 是 AI 辅助操作层
- **`kb` 工具**是命令行对接层。

其中的层次架构为：
- **主配置**：`.config/emacs/`（Git 子模块），入口见 `.config/emacs/AGENTS.md`
- **Agent 技能**：`.config/agents/skills/`，含 `knowledge-base`（检索写入）、`kb-curator`（策展维护）、`self-improving`（经验记录）等
- **CLI 工具**：`.local/bin/kb`，知识库增删查改的命令行入口

操作须知：
- 修改 Emacs 配置 → 进入 `.config/emacs/` 子目录
- 所有 `.el` 文件优先读 `;;; Commentary:` 注释
- 知识库相关 skill 定义在 `.config/agents/skills/` 下

路径速查（所有路径相对于本目录）：

| 用途             | 路径                                    |
| ---------------- | --------------------------------------- |
| Emacs 主配置     | `.config/emacs/`（Git 子模块）          |
| Agent Skills     | `.config/agents/skills/`                |
| kb CLI           | `.local/bin/kb`                         |
| 知识库根目录     | `~/Documents/Org/`                      |
| 经验卡片         | `~/Documents/Org/experiences/<类别>/`   |
| 模式文件         | `~/Documents/Org/patterns.org`          |
| 机器索引         | `~/Documents/Org/index.json`            |
| 收件箱           | `~/Documents/Org/inbox.org`             |
| 用户画像         | `~/Documents/Org/profile.org`           |o
| 对话历史         | `~/Documents/Org/conversations/`        |
