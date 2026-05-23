<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: GPL-3.0
-->

# Pi Agent 配置

本目录是 Pi Agent 的配置源文件，通过 GNU Stow 部署到 `~/.config/pi/`、`~/.local/share/pi/` 等 XDG 路径。

## 部署模型

```
dotfiles/mutable/pi/          → GNU Stow → 实际路径
├── .config/pi/               → ~/.config/pi/          (配置 + 扩展 + agent)
├── .local/bin/               → ~/.local/bin/          (启动脚本: pi, pi-acp, pi-update)
├── .local/share/pi/          → ~/.local/share/pi/     (辅助脚本 + npm 依赖)
├── .pi-lens/                 → ~/.pi-lens/            (pi-lens 缓存，gitignored)
├── .stow-local-ignore        → stow 排除规则
└── .gitignore                → git 排除规则（.pi-lens, node_modules, __pycache__）
```

`.stow-local-ignore` 排除了 `AGENTS.md`、`.gitignore`、`npm` 目录——这些不会进入 `~`。

**修改后无需重新 stow**（符号链接直接生效），除非新增文件需要 `stow -R pi`。

## 目录结构

```
.config/pi/
├── agents/          # Subagent 定义（YAML frontmatter + Markdown system prompt）
│   ├── scout.md        快速侦察员 (deepseek-v4-flash, thinking: low)
│   ├── researcher.md   文档检索专家 (deepseek-v4-pro, thinking: medium)
│   ├── planner.md      战略规划师 (GLM-5.1, no thinking override)
│   ├── oracle.md       架构顾问 (GLM-5.1, no thinking override)
│   ├── worker.md       自主深度工作者 (GLM-5.1, no thinking override)
│   └── reviewer.md     无情审查者 (GLM-5.1, no thinking override)
├── extensions/      # 本地扩展（TypeScript，Pi 启动时加载）
│   ├── tmux-subagents/  tmux 分屏 subagent 执行器 + plan-review-gate
│   ├── custom-shortcuts/ 快捷键覆盖（Shift+Tab → /plannotator）
│   └── global-context/  全局上下文注入（before_agent_start hook）
├── prompts/         # Prompt 模板（chain 定义）
│   ├── implement.md              scout(thorough) → planner → worker → reviewer
│   ├── implement-and-review.md   worker → reviewer → worker (fix)
│   ├── scout-and-plan.md         scout → planner
│   └── design-review-implement.md scout(thorough) → planner → oracle → worker → reviewer
├── APPEND_SYSTEM.md # 主 agent 附加系统提示：知识库优先、主动委派 subagent
├── settings.json    # 核心配置（见下方归属表）
├── models.json      # 自定义 provider/模型定义（zai provider）
├── keybindings.json # 快捷键绑定（当前仅清空默认 app.thinking.cycle）
└── plannotator.json # plannotator 扩展配置（planning phase 工具白名单）
```

## settings.json 配置归属

JSON 不支持注释，所有配置项的归属和维护责任记录在此。

**修改 settings.json 时必须同步更新本表。**

### pi 核心

| 配置项                 | 说明                                                              |
| ---------------------- | ----------------------------------------------------------------- |
| `defaultProvider`      | 默认 provider：当前为 `opencode-go`                               |
| `defaultModel`         | 默认模型：当前为 `kimi-k2.6`                                      |
| `defaultThinkingLevel` | 默认思考级别：`high`                                              |
| `npmCommand`           | npm 包管理器：`pnpm`                                              |
| `compaction`           | 上下文压缩策略（enabled, reserveTokens, keepRecentTokens）        |
| `retry`                | 请求重试策略（maxRetries, baseDelayMs, provider.maxRetryDelayMs） |
| `packages`             | npm 扩展包列表（见下方完整清单）                                  |
| `skills`               | skill 文件 glob：`~/.config/agents/skills/*`                      |
| `lastChangelogVersion` | 已读 changelog 版本，用于控制更新提示                             |
| `images`               | 图片处理（blockImages）                                           |
| `theme`                | UI 主题：`dark`                                                   |
| `showHardwareCursor`   | 是否显示硬件光标                                                  |
| `transport`            | 传输方式：`auto`                                                  |
| `collapseChangelog`    | 折叠 changelog                                                    |
| `quietStartup`         | 安静启动                                                          |

### npm 扩展包清单

当前安装的 packages（`settings.json` → `packages` 数组）：

- `npm:context-mode`、`npm:pi-mcp-adapter`、`npm:pi-web-access`
- `npm:@plannotator/pi-extension` — 规划模式扩展
- `npm:pi-powerline-footer`、`npm:pi-hashline-edit`、`npm:pi-lens`
- `npm:@ff-labs/pi-fff`、`npm:pi-cache-graph`
- `npm:@juicesharp/rpiv-todo`、`npm:@juicesharp/rpiv-advisor`、`npm:@juicesharp/rpiv-btw`
- `npm:@tmustier/pi-ralph-wiggum`

### npm:pi-powerline-footer

| 配置项      | 说明                                                  |
| ----------- | ----------------------------------------------------- |
| `powerline` | 状态栏配置（preset: default, path.mode: abbreviated） |

### 本地扩展: extensions/tmux-subagents/

| 配置项          | 说明                                                                                              |
| --------------- | ------------------------------------------------------------------------------------------------- |
| `tmuxSubagents` | subagent 运行配置（pollIntervalMs, panePrefix, keepResults, timeoutMs, maxTasks, maxConcurrency） |

源码：`extensions/tmux-subagents/index.ts` → `loadConfig()` 读取 `settings.tmuxSubagents`。

### 本地扩展: extensions/global-context/

| 配置项          | 说明                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------- |
| `globalContext` | 全局上下文注入（enabled, contextDir, extraFiles, maxFiles, maxBytesPerFile, maxTotalBytes） |

源码：`extensions/global-context/index.ts` → 读取 `settings.globalContext`。

## 模型体系

`models.json` 定义了自定义 `zai` provider（智谱 AI Coding Plan），当前不设置 Pi thinking level。`modelOverrides` 将内置 lowercase zai 模型的 `reasoning` 标记为 true/false，控制模型选择器的提示行为。scout/researcher 使用 Pi 内置 deepseek provider，以利用大上下文和 flash 速度。

| 模型                         | 能力                          | 用途                                          |
| ---------------------------- | ----------------------------- | --------------------------------------------- |
| `zai/GLM-5.1`                | 256K 上下文，reasoning: true  | 深度任务（worker, planner, oracle, reviewer） |
| `zai/GLM-5-Turbo`            | 256K 上下文，reasoning: true  | 快速任务备选                                  |
| `zai/GLM-4.7`                | 128K 上下文，reasoning: false | 降级备选                                      |
| `zai/GLM-4.5-Air`            | 非推理、128K 上下文           | 降级备选                                      |
| `deepseek/deepseek-v4-flash` | 大上下文、快速                | scout 快速侦察                                |
| `deepseek/deepseek-v4-pro`   | 大上下文                      | researcher 文档/资料调研                      |

**注意**：`defaultProvider`/`defaultModel` 可随时切换，当前指向 `opencode-go`/`kimi-k2.6`，不代表 zai 不可用。agent frontmatter 中的 `model` 字段独立指定，不受 defaultProvider 影响。

## Subagent 架构

### 设计原则

本架构遵循以下核心原则：

1. **规划者拥有 scope 并发布任务，不做编码**：写计划、读 handoff、决定下一步是规划者的工作。编辑文件、运行 git merge、内联修复冲突不是。
2. **规划者不知道谁接了任务**：脚本将每个任务路由到一个 agent。规划者的心智模型保持在任务层面。
3. **Worker 完全隔离**：一个任务、一个 repo 克隆、不与任何其他 agent 通信。完成时一个 handoff。
4. **通过 handoff 持续推进**：规划者收到迟到的 handoff 后可以重新规划。直到规划者决定停止发布才结束。
5. **传播而非同步**：兄弟之间不互通、层级之间不共享状态。每层只看到其子节点的 handoff。

### 节点类型

| 节点           | 运行循环？ | Scope                  | 输出                            |
| -------------- | ---------- | ---------------------- | ------------------------------- |
| Planner        | 是         | 整个用户目标           | 用户面向消息                    |
| Subplanner (↻) | 是         | 父 scope 的一个切片    | Handoff 给父节点                |
| Worker         | 否         | 一个具体任务           | Handoff 给发布它的 planner      |
| Verifier       | 否         | 一个目标任务的验收标准 | 判定 handoff 给发布它的 planner |

### Verification 级别

| 级别                 | 含义                        | 规划者响应           |
| -------------------- | --------------------------- | -------------------- |
| `live-ui-verified`   | 实际复现 bug 并确认修复消除 | 信任为已发布         |
| `unit-test-verified` | 目标测试覆盖变更路径并通过  | 非 UI bug 可接受     |
| `type-check-only`    | 仅类型检查/构建通过         | 弱，仅适合纯类型变更 |
| `verifier-blocked`   | 环境故障阻止验证            | 不算已验证，需重跑   |
| `verifier-failed`    | 验证运行但修复无效          | 需要后续修复任务     |

### 失败恢复策略

| 失败模式          | 策略                                                   |
| ----------------- | ------------------------------------------------------ |
| `cap-hit` / `oom` | 缩小范围重试：拆分更窄的任务、更紧的路径、更精简的目标 |
| `network-drop`    | 原样重试，视为瞬时故障                                 |
| `tool-error`      | 换模型重试                                             |
| `unknown`         | 原样重试一次，再失败则放弃                             |

同一任务重试 2 次后，优先放弃而不是第 3 次尝试，除非有具体证据表明下次会成功。

### 执行管线

subagent 执行分为三层：

1. **Pi 主会话** → 调用 `subagent` 工具（由 `tmux-subagents` 扩展注册）
2. **tmux-subagents 扩展** → 解析参数、发现 agent、创建 tmux 分屏、启动 wrapper
3. **subagent-wrapper.sh** → 解析 agent frontmatter、构造 `pi --mode json` 命令、管道到 `extract-pi-result.py`

```
主会话 → subagent tool
         ↓
    discoverAgents()    扫描 agents/*.md，解析 frontmatter
         ↓
    launchSingle/Parallel/Chain()   创建 runDir、status.json、分屏启动
         ↓
    subagent-wrapper.sh   (tmux 窗格内)
      ├─ parse_agent_md     提取 model/thinking/tools + system prompt body
      ├─ pi --mode json     运行独立 Pi 实例
      └─ extract-pi-result.py   解析 JSON 流，提取最终 assistant 文本
         ↓
    waitForCompletion()   轮询 status.json，超时/退出检测
```

### Chain 模板变量

prompt 模板（`prompts/*.md`）中嵌入的 JSON chain 支持：

- `{task}` — 用户输入的根任务（`params.task`）
- `{previous}` — 上一步 agent 的输出文本（pipeline 串联）

### Agent 快捷命令

tmux-subagents 扩展会为每个 agent 自动注册 `/<agent-name>` 命令（如 `/scout`、`/worker`），直接启动 single 模式 subagent。

### Plan Review Gate

`plan-review-gate.ts` 通过 Pi 的 `tool_call` 事件拦截 `plannotator_submit_plan`：

1. 首次提交 → block，reason 指示 LLM 调用 planner subagent 审查
2. 审查后再次提交 → 放行（`reviewedPlans` Set 避免循环）

**前提**：plannotator 已安装且 planning phase 启用了 `subagent` 工具（见 `plannotator.json`）。

## 扩展机制

所有扩展位于 `extensions/` 下，每个子目录含 `index.ts` 作为入口，导出 `default function(pi: ExtensionAPI)`。

### global-context（`before_agent_start` hook）

从 `$XDG_CONFIG_HOME/agents/context/` 和 `extraFiles`（含 `~/Documents/Org/profile.org`）读取 `.md` 文件，注入到每次 agent 交互的系统提示词中。有字节预算限制（默认 192KB 总量、64KB/文件、最多 8 文件）。

### custom-shortcuts（`onTerminalInput` hook）

拦截 Shift+Tab，替换为 `/plannotator` 命令提交。通过 `setEditorText` + 返回 `{ data: "\r" }` 实现，绕过 Pi 扩展 API 不走编辑器提交路径的限制。**副作用**：会清除用户当前输入，用 `setTimeout` 恢复。

### tmux-subagents

注册 `subagent` 工具和 `/agentname` 快捷命令。详见上方 Subagent 架构。

## 启动脚本

位于 `.local/bin/`：

| 脚本        | 作用                                      |
| ----------- | ----------------------------------------- |
| `pi`        | Pi Agent 主入口（调用 pi-xdg-runtime.sh） |
| `pi-acp`    | 自动 commit 推送工具                      |
| `pi-update` | Pi Agent 更新脚本                         |

## 辅助脚本

位于 `.local/share/pi/scripts/`：

| 脚本                   | 作用                                                                         |
| ---------------------- | ---------------------------------------------------------------------------- |
| `pi-xdg-runtime.sh`    | XDG 兼容层：初始化 XDG 变量、构建 compat tree、bwrap 绑定 `~/.pi` → XDG 路径 |
| `subagent-wrapper.sh`  | subagent 执行包装：解析 frontmatter、构造 pi 命令、捕获输出                  |
| `extract-pi-result.py` | Pi JSON 流解析器：提取最终 assistant 文本 + 元数据                           |
| `read-crush-key.sh`    | 从 crush.json 读取 provider API key                                          |

### pi-xdg-runtime.sh 关键行为

- `pi_prepare_compat_tree()` — 将 XDG 路径下的配置/数据通过符号链接映射到 Pi 期望的 `~/.pi/` 路径
- `pi_exec_xdg()` — 使用 bwrap 绑定挂载，让 Pi 进程看到 `~/.pi` 和 `~/.pi-lens`（实际指向 XDG 路径）
- `PI_XDG_BWRAP=0` 可跳过 bwrap，直接运行
- 包含锁文件机制（`.compat-tree.lock`）防止并发冲突
- 自动从旧 `~/.pi` 目录迁移数据（一次性，标记 `.migrated-from-home`）

### .local/share/pi/package.json

Pi 的 npm 依赖声明（`@earendil-works/pi-*`），通过 `pnpm install` 安装。`pi-xdg-runtime.sh` → `pi_ensure_installed()` 处理安装和 lockfile 同步。

## 修改约束

- **修改 agents/\*.md**：直接编辑，frontmatter 中的 `model` 必须使用已配置或 Pi 内置可用的 provider/model；保留 scout/researcher 的 deepseek 路由
- **修改 agents/\*.md 的 `thinking`**：仅对确认支持 thinking 的模型设置；zai 当前不要设置
- **修改 settings.json**：必须同步更新本文件的配置归属表
- **修改 models.json**：仅记录自定义 provider；内置 provider（如 deepseek）不要重复定义
- **修改 extensions/**：当前为直接加载的 TypeScript 文件，修改后重启 Pi Agent 会话并用 `pi --help` / 语法检查验证
- **新增 npm 包**：加入 settings.json 的 `packages` 数组，并在本文件记录其配置项
- **删除 npm 包**：同步从 settings.json 移除其配置项，并更新本文件

## 非显而易见的陷阱

- **Stow 不会链接 AGENTS.md 和 .gitignore**（被 `.stow-local-ignore` 排除），所以这些文件仅存在于仓库中
- **`.config/pi/npm` 被 stow 排除但被 gitignore 排除**——npm 包安装数据不应被 git 跟踪
- **Pi 内部仍硬编码 `~/.pi` 路径**，`pi-xdg-runtime.sh` 通过 bwrap 兼容层桥接；修改 XDG 路径配置后需验证 compat tree 是否正确
- **extensions/global-context 的 `resolveConfiguredPath`** 手动展开 `$XDG_CONFIG_HOME` 等（不依赖 shell），路径中含环境变量时用 `$VAR` 或 `${VAR}` 语法
- **subagent-wrapper.sh 默认工具为 `read,grep,find,ls`**（只读），agent frontmatter 的 `tools` 字段覆盖此默认值
- **agent frontmatter 的 `tools` 是逗号分隔字符串**（如 `tools: read, grep, find, ls`），由扩展代码 `split(",")` 解析
- **chain 中 `{previous}` 会替换为上一步的完整输出文本**，长输出可能导致 token 膨胀
- **subagent 的 status.json 在 wrapper 启动时写入 `running`**，完成后改为 `completed`/`failed`；主扩展轮询此文件判断状态
- **plan-review-gate 的 reviewedPlans 是内存 Set**，session 重启后清空
- **defaultProvider/defaultModel 与 agent frontmatter 的 model 独立**——切换默认模型不影响已有 agent 路由

## Handoff 格式规范

Worker 和 Verifier 的最终消息就是 Handoff，是 agent 间信息传递的唯一通道。主 agent 读取 handoff 来决定下一步。

### Worker Handoff 结构

```markdown
## Status

success | partial | blocked

## Branch

`<actual branch name>` (或 "(no branch)" 如果没有代码产出)

## What I did

- 高层摘要

## Measurements

- <metric>: <before> <op> <after>

## Verification

live-ui-verified | unit-test-verified | type-check-only | not-verified

## Notes, concerns, deviations, findings, thoughts, feedback

- 规划者需要知道的信息

## Suggested follow-ups

- 建议的后续任务
```

### Verifier Handoff 结构

```markdown
## Verification

live-ui-verified | unit-test-verified | type-check-only | verifier-blocked | verifier-failed

## Target

`<target-name>` on branch `<target-branch>`

## Execution

- <command run> → <outcome>
- <test suite> → <pass/fail counts>

## Findings

Per acceptance criterion:

- [x] <criterion text>: <evidence> (met | not met | n/a)
      Other findings (severity-ordered):
- (high) <finding>: evidence

## Notes & suggestions

- 规划者需要知道的信息
```

### 质量底线

- 无占位 TODO，每个公共函数必须有真实实现
- 无 `throw new Error("not implemented")` 除非在明确的断言辅助函数中
- UI/交互 bug：必须截屏或录屏作为证据
- 只注释非显而易见的 _why_，不写叙述性注释

## CLI 设计规范

本项目的辅助脚本（`pi-xdg-runtime.sh`、`subagent-wrapper.sh` 等）应遵循以下 agent 友好 CLI 设计原则：

1. **非交互优先**：每个输入都应能作为 flag，不依赖交互式提示
2. **--help 包含 Examples**：比文字说明更有效
3. **快速失败 + 可操作错误信息**：缺少 flag 时立即退出并给出正确示例
4. **幂等性**：同一命令运行两次应安全（无副作用或明确 "already done"）
5. **--dry-run**：预览计划后再提交
6. **一致性**：`resource + verb` 模式（如 `pi service list`、`pi config list`）
7. **结构化成功输出**：返回机器可用的数据（ID、URL、耗时）
