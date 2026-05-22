<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Pi Agent 配置

本目录是 Pi Agent 的配置源文件，通过 GNU Stow 链接到 `~/.config/pi/`。

## 目录结构

```
pi/
├── agents/          # Subagent 定义（frontmatter + system prompt）
│   ├── scout.md        快速侦察员 (deepseek-v4-flash, thinking: low)
│   ├── researcher.md   文档检索专家 (deepseek-v4-pro, thinking: medium)
│   ├── planner.md      战略规划师 (GLM-5.1, no thinking override)
│   ├── oracle.md       架构顾问 (GLM-5.1, no thinking override)
│   ├── worker.md       自主深度工作者 (GLM-5.1, no thinking override)
│   └── reviewer.md     无情审查者 (GLM-5.1, no thinking override)
├── extensions/      # 本地扩展（TypeScript）
│   ├── tmux-subagents/  tmux 分屏 subagent 执行器
│   └── global-context/  全局上下文注入
├── prompts/         # Prompt 模板（chain 定义）
│   ├── implement.md              worker 单步实施
│   ├── implement-and-review.md   worker → reviewer → worker (fix)
│   ├── scout-and-plan.md         scout → planner
│   └── design-review-implement.md scout → planner → oracle → worker → reviewer
├── APPEND_SYSTEM.md # 主 agent 附加系统提示：知识库优先、主动委派 subagent
├── settings.json    # 核心配置（见下方归属表）
└── models.json      # 自定义 provider/模型定义（zai；deepseek 使用 Pi 内置 provider）
```

## settings.json 配置归属

JSON 不支持注释，所有配置项的归属和维护责任记录在此。

**修改 settings.json 时必须同步更新本表。**

### pi 核心

| 配置项                 | 说明                                                              |
| ---------------------- | ----------------------------------------------------------------- |
| `defaultProvider`      | 默认 provider：`zai`                                              |
| `defaultModel`         | 默认模型：`GLM-5.1`                                               |
| `npmCommand`           | npm 包管理器：`bun`                                               |
| `compaction`           | 上下文压缩策略（enabled, reserveTokens, keepRecentTokens）        |
| `retry`                | 请求重试策略（maxRetries, baseDelayMs, provider.maxRetryDelayMs） |
| `packages`             | npm 扩展包列表                                                    |
| `skills`               | skill 文件 glob：`~/.config/agents/skills/*`                      |
| `lastChangelogVersion` | 已读 changelog 版本，用于控制更新提示                             |
| `images`               | 图片处理（blockImages）                                           |
| `theme`                | UI 主题：`dark`                                                   |
| `showHardwareCursor`   | 是否显示硬件光标                                                  |
| `transport`            | 传输方式：`auto`                                                  |
| `collapseChangelog`    | 折叠 changelog                                                    |
| `quietStartup`         | 安静启动                                                          |

### npm:pi-powerline-footer

| 配置项      | 说明                                                  |
| ----------- | ----------------------------------------------------- |
| `powerline` | 状态栏配置（preset: default, path.mode: abbreviated） |

### 本地扩展: extensions/tmux-subagents/

| 配置项          | 说明                                                         |
| --------------- | ------------------------------------------------------------ |
| `tmuxSubagents` | subagent 运行配置（pollIntervalMs, panePrefix, keepResults, timeoutMs, maxTasks, maxConcurrency） |

源码：`extensions/tmux-subagents/index.ts` → `loadConfig()` 读取 `settings.tmuxSubagents`。

### 本地扩展: extensions/global-context/

| 配置项          | 说明                                     |
| --------------- | ---------------------------------------- |
| `globalContext` | 全局上下文注入（enabled, contextDir, extraFiles, maxFiles, maxBytesPerFile, maxTotalBytes） |

源码：`extensions/global-context/index.ts` → 读取 `settings.globalContext`。

## 模型体系

默认主模型使用 zai（智谱 AI Coding Plan），自定义定义在 `models.json`；zai 当前不设置 Pi thinking level。`models.json` 同时用 `modelOverrides` 将 Pi 内置 lowercase zai 模型的 `reasoning` 关掉，避免模型选择器误提示这些模型支持 thinking。scout/researcher 使用 Pi 内置 deepseek provider，以利用 1M 上下文和 flash 速度。

| 模型              | 能力                | 用途                                                  |
| ----------------- | ------------------- | ----------------------------------------------------- |
| `zai/GLM-5.1`     | 256K 上下文，不设置 Pi thinking | 主模型、深度任务（worker, planner, oracle, reviewer） |
| `zai/GLM-5-Turbo` | 256K 上下文，不设置 Pi thinking | 快速任务备选                                          |
| `zai/GLM-4.7`     | 128K 上下文，不设置 Pi thinking | 降级备选                                              |
| `zai/GLM-4.5-Air` | 非推理、128K 上下文 | 降级备选                                              |
| `deepseek/deepseek-v4-flash` | 大上下文、快速 | scout 快速侦察 |
| `deepseek/deepseek-v4-pro` | 大上下文 | researcher 文档/资料调研 |

## Subagent 调度链

Prompts 目录中的 chain 定义决定了 subagent 的协作流程：

```
implement.md:              scout → planner → worker → reviewer
implement-and-review.md:   worker → reviewer → worker (fix)
scout-and-plan.md:         scout → planner
design-review-implement:   scout → planner → oracle → worker → reviewer
```

`tmux-subagents` 支持 `single`、`parallel`、`chain` 三种执行协议，prompt 模板中的 `chain` JSON 可直接由 `subagent` 工具执行。

## 修改约束

- **修改 agents/\*.md**：直接编辑，frontmatter 中的 `model` 必须使用已配置或 Pi 内置可用的 provider/model；保留 scout/researcher 的 deepseek 路由
- **修改 agents/\*.md 的 `thinking`**：仅对确认支持 thinking 的模型设置；zai 当前不要设置
- **修改 settings.json**：必须同步更新本文件的配置归属表
- **修改 models.json**：仅记录自定义 provider；内置 provider（如 deepseek）不要重复定义
- **修改 extensions/**：当前为直接加载的 TypeScript 文件，修改后重启 Pi Agent 会话并用 `pi --help` / 语法检查验证
- **新增 npm 包**：加入 settings.json 的 `packages` 数组，并在本文件记录其配置项
- **删除 npm 包**：同步从 settings.json 移除其配置项，并更新本文件
