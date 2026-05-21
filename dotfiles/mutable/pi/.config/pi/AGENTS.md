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
│   ├── scout.md        快速侦察员 (GLM-5-Turbo, thinking: low)
│   ├── researcher.md   文档检索专家 (GLM-5-Turbo, thinking: medium)
│   ├── planner.md      战略规划师 (GLM-5.1, thinking: high)
│   ├── oracle.md       架构顾问 (GLM-5.1, thinking: high)
│   ├── worker.md       自主深度工作者 (GLM-5.1, thinking: high)
│   └── reviewer.md     无情审查者 (GLM-5.1, thinking: high)
├── extensions/      # 本地扩展（TypeScript）
│   ├── tmux-subagents/  tmux 分屏 subagent 执行器
│   └── global-context/  全局上下文注入
├── prompts/         # Prompt 模板（chain 定义）
│   ├── implement.md              worker 单步实施
│   ├── implement-and-review.md   worker → reviewer → worker (fix)
│   ├── scout-and-plan.md         scout → planner
│   └── design-review-implement.md scout → planner → oracle → worker → reviewer
├── settings.json    # 核心配置（见下方归属表）
└── models.json      # 自定义 provider/模型定义（zai: GLM-5.1, GLM-5-Turbo, GLM-4.7, GLM-4.5-Air）
```

## settings.json 配置归属

JSON 不支持注释，所有配置项的归属和维护责任记录在此。

**修改 settings.json 时必须同步更新本表。**

### pi 核心

| 配置项                 | 说明                                                              |
| ---------------------- | ----------------------------------------------------------------- |
| `defaultProvider`      | 默认 provider：`zai`                                              |
| `defaultModel`         | 默认模型：`GLM-5.1`                                               |
| `defaultThinkingLevel` | 默认思考级别：`high`                                              |
| `npmCommand`           | npm 包管理器：`bun`                                               |
| `compaction`           | 上下文压缩策略（enabled, reserveTokens, keepRecentTokens）        |
| `retry`                | 请求重试策略（maxRetries, baseDelayMs, provider.maxRetryDelayMs） |
| `packages`             | npm 扩展包列表                                                    |
| `skills`               | skill 文件 glob：`./skills/*`                                     |
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
| `tmuxSubagents` | subagent 运行配置（pollIntervalMs, panePrefix, keepResults） |

源码：`extensions/tmux-subagents/index.ts` → `loadConfig()` 读取 `settings.tmuxSubagents`。

### 本地扩展: extensions/global-context/

| 配置项          | 说明                                     |
| --------------- | ---------------------------------------- |
| `globalContext` | 全局上下文注入（contextDir, extraFiles） |

源码：`extensions/global-context/index.ts` → 读取 `settings.globalContext`。

## 模型体系

全部使用 zai（智谱 AI Coding Plan）的模型，定义在 `models.json`。

| 模型              | 能力                | 用途                                                  |
| ----------------- | ------------------- | ----------------------------------------------------- |
| `zai/GLM-5.1`     | 推理、256K 上下文   | 主模型、深度任务（worker, planner, oracle, reviewer） |
| `zai/GLM-5-Turbo` | 推理、256K 上下文   | 快速任务（scout, researcher）                         |
| `zai/GLM-4.7`     | 推理、128K 上下文   | 降级备选                                              |
| `zai/GLM-4.5-Air` | 非推理、128K 上下文 | 降级备选                                              |

## Subagent 调度链

Prompts 目录中的 chain 定义决定了 subagent 的协作流程：

```
implement.md:              worker
implement-and-review.md:   worker → reviewer → worker (fix)
scout-and-plan.md:         scout → planner
design-review-implement:   scout → planner → oracle → worker → reviewer
```

## 修改约束

- **修改 agents/\*.md**：直接编辑，frontmatter 中的 `model` 必须为 zai 模型
- **修改 settings.json**：必须同步更新本文件的配置归属表
- **修改 models.json**：模型 ID 必须与 zai API 一致
- **修改 extensions/**：需要重新构建（`cd extensions/xxx && bun run build`）
- **新增 npm 包**：加入 settings.json 的 `packages` 数组，并在本文件记录其配置项
- **删除 npm 包**：同步从 settings.json 移除其配置项，并更新本文件
