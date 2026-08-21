# atelier — Subagent 可视化执行平台

基于 tmux 分屏的 subagent 执行扩展。通过 `subagent` 工具或 `/agentname` 快捷命令启动子 agent，在 tmux pane 内可视化执行，结果通过 workfile + result.md 结构化回收。

设计文档：`docs/atelier.md`（仓库根）。

## 目录结构

<!-- structor:begin depth=4 -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
atelier/
├── context/
│   ├── agents/
│   │   ├── griller.md
│   │   ├── oracle.md
│   │   ├── planner.md
│   │   ├── researcher.md
│   │   ├── reviewer.md
│   │   ├── scout.md
│   │   ├── visual.md
│   │   └── worker.md
│   └── prompts/
│       ├── design-review-implement.md
│       ├── implement-and-review.md
│       ├── implement.md
│       ├── parallel-research.md
│       ├── parallel-workers.md
│       ├── research-and-implement.md
│       └── scout-and-plan.md
├── core/
│   ├── config.ts
│   ├── context.ts
│   ├── discovery.ts
│   ├── schedule.ts
│   ├── schemas.ts
│   ├── system-agents.ts
│   └── types.ts
├── lifecycle/
│   ├── checkpoint.ts
│   ├── resume.ts
│   └── workflow.ts
├── registry/
│   ├── completion-gate.ts
│   ├── orphan-recovery.ts
│   ├── registry.ts
│   ├── return-header.ts
│   └── stuck-detector.ts
├── runtime/
│   ├── multiplexer/
│   │   ├── detect.ts
│   │   ├── herdr.ts
│   │   ├── tmux.ts
│   │   └── types.ts
│   ├── formatting.ts
│   ├── launcher.ts
│   ├── monitor.ts
│   ├── runner.ts
│   ├── session-log.ts
│   └── workfile.ts
├── scripts/
│   ├── extract-pi-result.py
│   └── subagent-wrapper.sh
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── README.md
├── index.ts
└── package.json
```

<!-- /structor -->

## 按职能分层

依赖方向无环：`core` ← `runtime` / `registry` / `lifecycle` ← `index`。

| 目录                   | 职责                                   | 关键文件                                                                                                                                                                                                         |
| ---------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `core/`                | 配置/类型/发现（无外部循环依赖）       | `types.ts`（接口 + DEFAULT_CONFIG）、`config.ts`（atelier.json 解析）、`discovery.ts`、`schemas.ts`、`context.ts`（subagent-only 切片 + agent 路径解析）、`schedule.ts`（模型时段 DSL）、`system-agents.ts`      |
| `context/`             | 插件内置 agent / prompt 模板（自包含） | `agents/*.md`（8 个 agent 定义，含 griller）、`prompts/*.md`（7 个链路模板）                                                                                                                                     |
| `runtime/`             | 执行链路（多路复用器 → 监控 → 编排）   | `launcher.ts`（分屏，调 backend 接口）、`monitor.ts`（轮询 + return-header 解析，multiplexer 无关）、`runner.ts`（runChain/Parallel/Fallback + schedule 过滤）、`workfile.ts`、`session-log.ts`、`formatting.ts` |
| `runtime/multiplexer/` | 多路复用器后端抽象（tmux/herdr）       | `types.ts`（MultiplexerBackend 接口）、`detect.ts`（HERDR_ENV/$TMUX 检测）、`tmux.ts`、`herdr.ts`                                                                                                                |
| `scripts/`             | pane 内执行脚本（自包含，随插件分发）  | `subagent-wrapper.sh`（subagent 执行包装）、`extract-pi-result.py`（JSONL→彩色终端流）                                                                                                                           |
| `registry/`            | 状态索引与治理（SQLite + 恢复层）      | `registry.ts`（SQLite 全局索引）、`orphan-recovery.ts`、`stuck-detector.ts`、`return-header.ts`、`completion-gate.ts`                                                                                            |
| `lifecycle/`           | 长程任务生命周期                       | `checkpoint.ts`（跨崩溃 checkpoint）、`workflow.ts`（可视化 workflow）、`resume.ts`（续跳）                                                                                                                      |

## Agent / Prompt 路径解析

agent/prompt `.md` 源文件位于插件内置 `context/{agents,prompts}/`（atelier 作为独立 pi-package 自包含）。所有读取点走 `core/context.ts` 的统一解析器：

| 读取点                                   | 用途                                        | 解析方式                                    |
| ---------------------------------------- | ------------------------------------------- | ------------------------------------------- |
| `core/discovery.ts`                      | `discoverAgents/discoverPrompts`            | `getAgentDirs()/getPromptDirs()` 多目录扫描 |
| `runtime/launcher.ts`                    | `prepareAgentPrompt`（subagent 启动）       | `resolveAgentFile(name)` 按优先级查找       |
| `index.ts` `loadMainSessionAgentContext` | 主会话 worker/planner/reviewer/griller 注入 | `resolveAgentFile(name)`                    |
| `scripts/subagent-wrapper.sh`            | `parse_agent_md`（pane 内 bash）            | `SCRIPT_DIR/../context/agents` 相对解析     |

**优先级**（同名 agent/prompt 按此顺序去重，先找到的赢）：

1. 插件内置 `context/{agents,prompts}/`（atelier 自带定义）
2. `getAgentDir()/{agents,prompts}/`（`~/.config/pi/agents/`，用户自定义，兼容旧路径）

TS 端用 `import.meta.url` 定位插件根目录；bash 端硬编码 `$XDG_CONFIG_HOME/pi/extensions/atelier/context/`。

## 主会话上下文注入

`index.ts` 的 `before_agent_start` hook 按以下优先级向**主会话** systemPrompt 追加 agent 行为上下文：

1. **命令注入标记**（最高）：`/<agentname> <task>` 在空上下文（无 user 消息）下触发。命令 handler 用 `pi.appendEntry("atelier:context-inject", { agent })` 写隐藏标记，hook 读到后追加对应 agent 的 prompt（剥离 subagent-only 段）并清除标记（一次性注入）。这让主 agent 以 `/reviewer` 等身份直接执行 task，而非启动独立 subagent pane。
2. **plan 模式**：plannotator 激活时注入 `planner.md`。
3. **默认**：注入 `worker.md`。

非空上下文（已有对话）下，`/<agentname> <task>` 走原 `launchSingle` 路径启动独立 subagent pane。

## 执行管线

```
subagent({...}) / /agentname
  → index.ts execute()        模式分流 + worker-single 警告
  → runner.ts                 executeWithFallback / runChain / runParallelBatches
                              resolveModelChain 按 modelSchedules 过滤时段禁用模型
  → launcher.ts launchSingle  生成 runId → 写 status.json{running} → backend.splitAbove/Right
  → wrapper.sh (独立 pane)    pi --mode json → extract-pi-result.py → 写 result.md + status.json{completed}
  → monitor.ts waitForCompletion  轮询 status.json → 解析 Return Header → 同步 registry
  → workfile.ts ensureWorkfile     兜底持久化（agent 未自写时）
```

**多路复用器**：`launcher.ts` 调 `detectBackend()`（`HERDR_ENV=1`→herdr，`$TMUX`→tmux）获取 `MultiplexerBackend` 实例，通过 `splitAbove/splitRight/setTitle/refocus` 控制 pane。tmux 新 pane 在上方，herdr 在下方——纯界面差异，monitor 基于 status.json 文件轮询不受影响。

**runId 格式**（`runtime/launcher.ts` generateRunId）：`sa-{base36ts}-{3bytehex}`，例 `sa-ltj3m2x0-a1b2c3`。系统子 agent 用 `sys-` 前缀（`core/system-agents.ts` generateSystemRunId）。

**run 目录**（`$XDG_CACHE_HOME/pi/subagents/{runId}/`）：`task.md`、`status.json`、`subagent-prompt.md`（注入了 CAPABILITY_SELF_CHECK + RETURN_FORMAT_INSTRUCTION）、`result.md`、`stderr.log`。

## Plan Review Gate（多轮对抗式诘问）

`index.ts` 的 `tool_call` hook 拦截 `plannotator_submit_plan`，强制计划提交前经过多轮对抗式诘问（grill）：

1. **首次 submit_plan** → `block: true`，注入 `griller.md` 方法论 + 计划路径，要求主会话与用户多轮诘问（一次一个问题，每问附推荐答案，事实查环境而非问用户）。
2. **多轮对话**：主 agent 扮演 griller，逐项压测计划的假设/边界/替代方案/架构/回滚，直到与用户达成共识。
3. **再次 submit_plan** → 放行，保存计划到 `.agents/current-plan.md`。

`reviewedPlans` Set 跟踪：首次拦截时 add(planFilePath)，二次放行时 delete。`buildPlanReviewGatePrompt()` 运行时调 `loadMainSessionAgentContext("griller")` 加载方法论 body，griller.md 缺失时降级为简短兜底维度。

## 配置

atelier 配置从 `~/.config/pi/atelier.json`（独立文件，推荐）或 `settings.json` 的 `atelier` 字段（向后兼容）加载，查找顺序：atelier.json > agent dir/settings.json > ~/.config/pi/settings.json。

关键字段（`core/types.ts` SubagentConfig）：

| 字段             | 说明                                                                                                                                                                             |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tiers`          | tier 名 → {model, fallback[]} 映射（agent frontmatter `tier:` 引用）                                                                                                             |
| `modelSchedules` | 模型名 → {allow?:[], deny?:[]} 时段限制（按模型名索引，跨 tier 生效）。`core/schedule.ts` 的 DSL：`{deny:["Mon-Fri 14:00-18:00"]}` / `{allow:["22:00-08:00"]}`（跨午夜自动展开） |
| `defaultTier`    | agent frontmatter 无 tier 时的回退 tier                                                                                                                                          |

## Registry / 持久化层

- **status.json 是 single source of truth**；SQLite registry（`$XDG_DATA_HOME/pi/atelier-registry.db`）是查询视图，崩溃可丢（删 .db 下次启动 `rebuildFromStatusFiles` 自动重建）。
- 用 pi 运行时（Bun）内置的 `bun:sqlite`（非 `node:sqlite`——pi 是 Bun 单文件构建，不提供 `node:sqlite` 模块）。零新依赖，非实验性 API。
- 启动三步（best-effort，不阻塞扩展加载）：`rebuildFromStatusFiles` → `orphanRecovery` → `startStuckDetector`（后台 fiber，`unref` 不阻塞退出）。
- schema 演进：`SCHEMA_VERSION` + `migrate()`（`PRAGMA user_version` + `ALTER TABLE ADD COLUMN`）。

## 长程任务恢复（checkpoint / workflow / resume）

- `runChain` 每完成一步写 **checkpoint**（`lifecycle/checkpoint.ts`，跨崩溃恢复用）+ **workflow**（`lifecycle/workflow.ts`，可视化查看用）。两者同存于 `.agents/workflows/`：checkpoint 文件名 `{parentRunId}.json`（`sa-` 前缀），workflow 文件名 `{wf-id}.json`（`wf-` 前缀）。
- `listWorkflows` 只列 `wf-` 前缀文件，避免 checkpoint 被误判为 corrupt。
- `/atelier-resume <parentRunId>`：读 checkpoint → 把剩余 step 转 chainEntries → 调 `runChain` 真实 dispatch。**续跳会生成新的 parentRunId**（原 checkpoint 作历史保留）；崩溃前的 `{previous}` 用 `inheritedContextSnapshot`（前 2000 字）近似替换——这是设计内的降级。

## Return Header 协议

子 agent 在 final message 顶部写 `**Status**: success|partial|failed|blocked` + `**Summary**:`，由 `registry/return-header.ts` 结构化解析后写入 registry。指令通过 `launcher.ts prepareAgentPrompt` 注入 `subagent-prompt.md`。LLM 不写则降级为 `return_status:"unknown"`。

## 修改约束

- **内置脚本** `subagent-wrapper.sh` / `extract-pi-result.py` 在 `scripts/`（随插件自包含分发）。它们在 spawned pane 内作为独立进程运行（tmux/herdr `split`+`run` 调用），只写 status.json/result.md，不知 SQLite 存在——atelier 是唯一的 SQLite writer。
- **多路复用器后端**：`runtime/multiplexer/` 抽象了 tmux/herdr 差异。`launcher.ts` 调 `MultiplexerBackend` 接口，`detectBackend()` 按 `HERDR_ENV=1`/`$TMUX` 自动选择。新增多路复用器支持只需实现接口 + 在 `detect.ts` 加检测分支。
- **模型时段限制**：`core/schedule.ts` 提供 allow/deny DSL，`runner.ts` 的 `resolveModelChain` 按 `config.modelSchedules[modelName]` 过滤。时段配置在 `atelier.json` 的 `modelSchedules` 字段（按模型名索引，跨 tier 生效）。
- **completion-gate.ts** 的 `isTaskToolAvailable()` 当前恒 false（pi 无 task 工具），`decide()` 是 no-op。架构保留待 pi 接入 task 工具后激活，不要误删。
- **CAPABILITY_SELF_CHECK**（`runtime/launcher.ts`）硬注入所有 subagent prompt——设计决策，所有 subagent 无条件获得能力自检。
- 语法验证（容器无 tsc）：`node --experimental-strip-types --check <file.ts>`（类型剥离语法校验，抓语法/import 错误但不抓类型错误；注意 `--check` 模式不支持 non-exported `interface`/`type` 声明，用 `export` 或在 run mode 验证）。最终运行回归靠 `blue rebuild` + 跑 pi。
- **禁止 AI agent 自行 `blue rebuild` / `guix system reconfigure`**（见仓库根 AGENTS.md）。

## 提交与版本发布

atelier 作为独立 pi-package（`github.com/ShineBreaker/pi-atelier`）发布，commit 与发版遵守以下约定。

### Commit 拆分粒度

**一个 commit 对应一个独立的原子变更点**。改了一处 bug + 顺手清理了一处死代码 + 改了一处文档 → 拆成 3 个 commit，不要合并。

- **FIX** — 修复 bug，独立成 commit。哪怕只是 1 行（如 `registerRun` 漏传 `runDir`），也单独提交。
- **FEATURE** — 新能力。一个 feature 一个 commit。如果一个 feature 跨多个文件（如路径解析涉及 `core/context.ts` + `core/discovery.ts` + `runtime/launcher.ts`），整组打包成 1 个 commit，因为它们逻辑上不可分。
- **DOCS** — 文档改动独立成 commit，与代码 commit 分离，便于 `git log --grep=DOCS` 检索。
- **UPDATE** — 依赖升级、版本 bump、submodule 指针更新。
- **REFACTOR** — 重构（无功能变化）。与 FEATURE 严格区分：改完应通过原有测试。
- **INITIAL** — 仓库首次引导。

### Commit 消息格式

```
TYPE: (scope) 一句话标题

详细说明：
- 改动动机（为什么改）
- 关键决策（与备选方案对比的理由）
- 影响范围（哪些文件、哪些 API、是否需 migration）

Refs: #issue (如有)
```

**风格约束**：

- 标题 ≤ 72 字，使用中文句号结尾
- `scope` 用文件名或目录名（如 `launcher.ts`、`路径解析`）
- body 每行 ≤ 100 字，使用项目内统一的"动机 / 决策 / 影响"三段式
- 涉及多文件时 body 列出文件清单 + 各自改动
- **不要**用 `git commit -am` 一把梭，必须 `git add` 选择性暂存
- **必须** GPG 签名：`git config commit.gpgsign=true` 已配置，使用现有密钥 `62711D5E9CCDEC6907CADBF88637132222571907`

### CHANGELOG

每次发版必须更新根目录的 `CHANGELOG.md`（[Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 风格 + [语义化版本](https://semver.org/lang/zh-CN/)）。

- **新增版本段**：在文件顶部 `## [X.Y.Z] - YYYY-MM-DD`，按 `### Fixed / ### Added / ### Changed / ### Removed / ### Deprecated / ### Security` 分类
- **正文面向用户**：用业务语言描述变更带来的影响，不堆 API/行号
- **附录面向开发者**：在版本段后加 `## 技术细节 / Migration Notes`（同文件或单独文件均可），含 schema 变更、path 兼容矩阵、已知问题
- **关联 commit 表**：列出本版本所有 commit 哈希 + 标题 + scope，方便溯源
- **早期版本**：文件底部保留各历史版本段（不要合并或删除），形成可追溯的发布史
- **CI/CD 不强求**：手工维护即可（atelier 节奏手动发版，无 CI 流水线）

### 版本号

遵循 [语义化版本](https://semver.org/lang/zh-CN/) `MAJOR.MINOR.PATCH`：

- **MAJOR**：破坏性 API 变更（schema 不兼容、行为语义变化、required 配置项新增）
- **MINOR**：新功能（向后兼容）
- **PATCH**：bug 修复（向后兼容）

特殊情形：

- 初始开发阶段（< 1.0.0）：可自由升降级，每次发版都视为潜在 MAJOR
- `0.1.0` → `0.1.1`：仅 PATCH（仅 bug fix + 文档）
- `0.1.1` → `0.2.0`：新能力（向后兼容）
- `0.x.y` → `0.(x+1).0`：API 变更

### 发版流程

1. **整理 commit 历史**：`git log v0.X.Y..HEAD` 确认本次发版包含的 commit
2. **更新 CHANGELOG.md**：在文件顶部新增 `## [X.Y.Z] - YYYY-MM-DD` 段，列出所有变更
3. **bump package.json 版本号**：`build(package.json): bump version` 单独 commit
4. **创建 git tag**：`git tag -s v0.X.Z -m "atelier v0.X.Z"` （GPG 签名 tag）
5. **推送**：先 `git push origin main`，再 `git push origin v0.X.Z`
6. **GitHub Release**（可选）：在 GitHub UI 基于 tag 创建 release notes，可直接复制 CHANGELOG 段
7. **父仓库 bump submodule 指针**（在 Guix-configs 父仓库）：单独 commit `build(atelier): bump submodule to 0.X.Z`

### 发版时 checklist

```
□ 所有目标 commit 已合并到 main
□ CHANGELOG.md 顶部新增版本段，含 Fixed/Added/Changed 分类
□ package.json version 已 bump
□ 语法验证通过（node --experimental-strip-types --check 所有 .ts）
□ 跨模块符号引用验证通过
□ git tag -s vX.Y.Z 已创建
□ 推送 main + tag
□ 父仓库 submodule 指针已 bump
```

### 反模式（不要做）

- 把多个不相关变更塞进 1 个 commit
- 使用 `git commit -am "fix stuff"`（必须明确 add + 写有意义的消息）
- 跳过 CHANGELOG 直接发版
- 不 bump package.json 就发版
- 改完代码不跑 `node --check` 就提交
- 推送前未验证 submodule pointer（父仓库 bump 与子模块 HEAD 不一致会导致构建失败）
