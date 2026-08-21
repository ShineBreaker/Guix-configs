# Changelog

atelier 所有值得注意的变更都会记录在此文件。

格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-08-04

### Added

- **herdr 多路复用器支持**：atelier 不再 tmux 专有。新增 `runtime/multiplexer/`
  抽象层（`MultiplexerBackend` 接口 + `TmuxBackend` + `HerdrBackend`），
  `detectBackend()` 按 `HERDR_ENV=1`/`$TMUX` 自动选择。在 herdr 内运行 pi 时，
  subagent 通过 `herdr pane split/run/close` 可视化执行，行为对等 tmux 路径。

- **模型使用时间限制**：新增 `core/schedule.ts` DSL 解析器 + `runner.ts`
  `resolveModelChain` 时段过滤。配置在 `atelier.json` 的 `modelSchedules` 字段
  （按模型名索引，跨 tier 生效）：`{ "zai/GLM-5.2": { "deny": ["Mon-Fri 14:00-18:00"] } }`。
  落在禁用窗口的模型自动跳过（每跳过一个 console.warn），全链禁用时降级
  defaultModel。支持 `allow`/`deny`、星期段（`Mon-Fri`/`Sat,Sun`）、跨午夜
  （`22:00-08:00` 自动展开）。

- **独立配置文件**：atelier 配置可从 `~/.config/pi/atelier.json` 加载
  （整文件即配置，优先级最高），不再强制塞在 `settings.json` 的 `atelier`
  字段里。两种路径共存，向后兼容。

- **griller agent + 对抗式诘问**：新增 `context/agents/griller.md`，承载
  grilling 方法论（逐个提问、决策树遍历、每问附推荐答案、事实查环境）。

- **脚本内化**：`subagent-wrapper.sh` + `extract-pi-result.py` 从外部
  `stow/pi/.local/share/pi/scripts/` 内化到插件 `scripts/` 目录。恢复
  0.1.1→0.2.0 之间因外部脚本丢失导致的功能性损坏，让 atelier 成为自包含
  pi-package。

### Changed

- **Plan review gate 重构**：拦截 `plannotator_submit_plan` 后，不再委派
  oracle subagent 做一次性审查，改为把 `griller.md` 方法论注入主会话
  systemPrompt，让主 agent 与用户做多轮对抗式诘问（一次一个问题，每问附
  推荐答案），达成共识后才放行提交。grilling 本质是主会话交互式流程，
  委派给独立 subagent 会丢失「逐个提问、等用户反馈」的闭环。

- **launcher 去 tmux 硬编码**：`launchSingle`/`launchParallel` 改调
  `MultiplexerBackend` 接口，删除 `tmuxExec`/`splitAboveCurrentPane` 等
  tmux 专有函数。`paneIsAlive`/`killPane` 保留为公共导出（monitor/runner
  multiplexer 无关），改为薄包装委托 `detectBackend()`。

### Fixed

- **subagent-wrapper.sh KEEP_PANE 多路复用器感知**：`PI_SUBAGENT_KEEP_PANE=1`
  的 pane 保留检查从仅 `$TMUX` 扩展为 `$TMUX || $HERDR_ENV`，herdr 内也生效。

### Removed

- **移除弃用的 `/run-plan` + `/loop` 命令**：loopctl 前端薄包装，loopctl
  本身已弃用（父仓 `5aae9f6e`），这两个命令入口随之删除。plan review gate
  放行后用户直接按计划实施即可。
- 删除 `load_subagents_config()`（读已废弃的 `~/.config/pi/subagents.json`，
  per-agent model 配置已被 tier 系统取代）。
- 删除 `TOP_ROW_PERCENT` 常量（tmux 专有，ratio 化后不再需要）。

### 关联提交

| 范围                           | Commit    | 说明                                              |
| ------------------------------ | --------- | ------------------------------------------------- |
| `core/config.ts`               | `caf6b1d` | FEATURE: 支持 atelier.json 独立配置文件           |
| `core/schedule.ts`             | `556d90a` | FEATURE: 时间窗口 DSL 解析器                      |
| `runtime/runner.ts`            | `df607d6` | FEATURE: resolveModelChain 按时段过滤模型         |
| `context/agents/griller.md`    | `e0b1445` | FEATURE: grilling 方法论 agent 定义               |
| `index.ts`                     | `e5af262` | REFACTOR: plan review gate 改为注入 grill 方法论  |
| `scripts/`                     | `6382ef2` | FEATURE: 内化 wrapper + extract 脚本              |
| `runtime/launcher.ts`          | `d1ab274` | REFACTOR: wrapper 路径改从 plugin root 解析       |
| `scripts/subagent-wrapper.sh`  | `edd62b2` | CLEANUP: 移除 legacy subagents.json + 硬编码路径  |
| `runtime/multiplexer/types.ts` | `9972ce8` | REFACTOR: 抽 MultiplexerBackend 接口              |
| `runtime/multiplexer/tmux.ts`  | `a402b70` | REFACTOR: 迁出 TmuxBackend                        |
| `runtime/multiplexer/herdr.ts` | `6375075` | FEATURE: HerdrBackend                             |
| `runtime/launcher.ts`          | `ad79b4a` | REFACTOR: 改调 backend 接口                       |
| `scripts/subagent-wrapper.sh`  | `48fd640` | FIX: KEEP_PANE 块 multiplexer 感知                |
| `index.ts`                     | `8437de9` | REMOVE: 移除弃用的 /run-plan + /loop loopctl 命令 |

---

## 技术细节 / Migration Notes

### 1. 配置迁移（settings.json → atelier.json）

旧配置（`settings.json` 内）：

```json
{ "atelier": { "defaultTier": "pro", "tiers": {...} } }
```

新配置（`~/.config/pi/atelier.json`，推荐）：

```json
{
  "defaultTier": "pro",
  "tiers": { "ultra": { "model": "...", "fallback": [...] }, ... },
  "modelSchedules": { "zai/GLM-5.2": { "deny": ["Mon-Fri 14:00-18:00"] } }
}
```

`config.ts` 查找顺序：atelier.json > agent dir/settings.json > ~/.config/pi/settings.json。
旧的 settings.json#atelier 仍生效（向后兼容），但建议迁移到独立文件。

### 2. 多路复用器后端

新增 `runtime/multiplexer/`：

- `types.ts` — `MultiplexerBackend` 接口（currentPaneId/splitAbove/splitRight/setTitle/refocus/isAlive/kill）
- `detect.ts` — 按 `HERDR_ENV=1`/`$TMUX` 选择后端
- `tmux.ts` — tmux 实现（从 launcher.ts 迁出，行为字节级一致）
- `herdr.ts` — herdr 实现（split 两步：pane split + pane run；kill=pane close）

差异接受：tmux 新 pane 在主 pane 上方，herdr 在下方。monitor.ts 基于
status.json 文件轮询，multiplexer 无关，零改动。

### 3. 脚本内化路径变化

| 旧路径（已废弃）                                 | 新路径                                  |
| ------------------------------------------------ | --------------------------------------- |
| `$XDG_DATA_HOME/pi/scripts/subagent-wrapper.sh`  | `<plugin>/scripts/subagent-wrapper.sh`  |
| `$XDG_DATA_HOME/pi/scripts/extract-pi-result.py` | `<plugin>/scripts/extract-pi-result.py` |

`launcher.ts` 的 `getScriptsDir()` 改用 `getPluginRoot()/scripts`。
wrapper 内的 `PLUGIN_AGENTS_DIR` 从硬编码 XDG 改为 `SCRIPT_DIR/../context/agents`。

### 4. 兼容性矩阵

| 项               | 0.1.1                 | 0.2.0                            |
| ---------------- | --------------------- | -------------------------------- |
| 多路复用器       | tmux only             | tmux + herdr                     |
| 配置文件         | settings.json#atelier | atelier.json（+ 旧路径兼容）     |
| 模型时段限制     | 无                    | modelSchedules（allow/deny DSL） |
| plan review gate | 委派 oracle subagent  | 主会话多轮 grill                 |
| 脚本位置         | 外部 stow 部署        | 插件内置 scripts/                |
| schema 版本      | v2                    | v2（无变化）                     |

---

## [0.1.1] - 2026-07-03

### Fixed

- **SQLite 写入崩溃**：`launchSingle` 调用 `registerRun` 时漏传 `runDir`，
  导致 `undefined` 绑定到 SQLite 参数 4（schema 要求 `run_dir TEXT NOT NULL`），
  抛出 `TypeE: Provided value cannot be bound to SQLite parameter 4`，
  整个 subagent 启动链路静默失败，仅在 console.warn 留下告警。
  对齐 `launchParallel` 的调用约定后修复。

- **Agent/prompt 读取路径失效**：agent/prompt `.md` 源文件从
  `~/.config/pi/agents/` 迁到插件内置 `context/{agents,prompts}/` 后，
  原 `getAgentDir()/agents` 读取路径全部失效，部署的 symlink 成断链，
  `discoverAgents()` 返回空数组，所有 subagent 启动找不到 agent .md。
  引入统一路径解析层修复（见下方 FEATURE）。

- **subagent-wrapper.sh 断链失败**：bash 端的 `parse_agent_md` 同样硬编码
  `~/.config/pi/agents`，与 TS 端策略对齐为多路径回退。

### Added

- **统一 agent/prompt 路径解析层**（`core/context.ts`）：新增
  `getPluginRoot()`（用 `import.meta.url` 定位插件根）、
  `getAgentDirs()` / `getPromptDirs()`（多候选目录列表）、
  `resolveAgentFile(name)`（按优先级查找）。被 `discoverAgents`、
  `discoverPrompts`、`prepareAgentPrompt`、`loadMainSessionAgentContext` 复用。
  优先级：插件内置 `context/{agents,prompts}/` > `getAgentDir()/{agents,prompts}/`
  （兼容用户自定义 agent）。同名 agent 插件内置赢，后扫到的跳过。

- **/&lt;agentname&gt; 空上下文注入**：当主会话还没有任何 user 消息时，
  `/<agentname> <task>` 不再启动独立 subagent pane，而是把对应 agent
  的 prompt 注入当前主会话的 systemPrompt，让主 agent 以该 agent
  身份直接执行 task。命令处理程序用 `appendEntry("atelier:context-inject", ...)`
  写隐藏标记，`before_agent_start` 钩子读到后追加 prompt 并清除标记
  （一次性注入）。优先级：**命令注入 > plan 模式 (planner) > 默认 (worker)**。
  非空上下文维持原 `launchSingle` 行为。

- **Agent/prompt 目录自包含**：atelier 作为独立 pi-package，agent 定义
  (7 agents) 与 prompt 模板 (7 templates) 全部内嵌在 `context/`
  目录中，不再依赖外部部署。

### Changed

- **AGENTS.md 文档更新**：目录树补 `context/agents` + `context/prompts`；
  新增 "Agent/Prompt 路径解析" 一节（4 个读取点 + 优先级策略）；
  新增 "主会话上下文注入" 一节（三级优先级）。

### 关联提交

| 范围                                    | Commit    | 说明                                     |
| --------------------------------------- | --------- | ---------------------------------------- |
| `atelier` 子模块                        | `93cf4ec` | FIX: `registerRun` 补 `runDir`           |
| `atelier` 子模块                        | `4b8de46` | FEATURE: 多目录路径解析                  |
| `atelier` 子模块                        | `f7e30b3` | FEATURE: /&lt;agentname&gt; 空上下文注入 |
| `atelier` 子模块                        | `e4e545e` | DOCS: AGENTS.md 路径解析/注入说明        |
| `atelier` 子模块                        | `d15d7e2` | UPDATE: package.json 0.1.0 → 0.1.1       |
| 父仓库 `stow/pi/.../wrapper.sh`         | `e75298f` | FIX: bash 端 `resolve_agent_file`        |
| 父仓库 `stow/pi/.../extensions/atelier` | `a9cde8f` | UPDATE: bump submodule → 0.1.1           |

---

## 技术细节 / Migration Notes

面向从 0.1.0 升级或自编译部署的开发者。

### 1. SQLite schema 兼容性

修复 A 涉及 `registerRun` 写入参数 4（`run_dir`）的修复，不引入 schema
变更。现有 `$XDG_DATA_HOME/pi/atelier-registry.db` 无需重建，启动时
`rebuildFromStatusFiles` 会自然重新填充 `run_dir`。

### 2. 路径解析层

新模块 `core/context.ts`（依赖 `getAgentDir()` from `@earendil-works/pi-coding-agent`，
`import.meta.url` from `node:url`）。被以下 4 个读取点复用：

| 读取点                                                | 用途                                  | 解析方式                                           |
| ----------------------------------------------------- | ------------------------------------- | -------------------------------------------------- |
| `core/discovery.ts`                                   | `discoverAgents/discoverPrompts`      | `getAgentDirs()/getPromptDirs()` 多目录扫描 + 去重 |
| `runtime/launcher.ts`                                 | `prepareAgentPrompt`（subagent 启动） | `resolveAgentFile(name)`                           |
| `index.ts` `loadMainSessionAgentContext`              | 主会话 worker/planner/reviewer 注入   | `resolveAgentFile(name)`                           |
| `stow/pi/.local/share/pi/scripts/subagent-wrapper.sh` | `parse_agent_md`（pane 内 bash）      | `resolve_agent_file()` 函数（与 TS 端策略一致）    |

**bash 端 fallback 路径**（与 TS 端 `getAgentDirs()` 一致）：

```bash
PLUGIN_AGENTS_DIR="$XDG_CONFIG_HOME/pi/extensions/atelier/context/agents"
USER_AGENTS_DIR="$XDG_CONFIG_HOME/pi/agents"
```

### 3. 上下文注入协议

新增内部自定义 entry 类型 `CustomEntry`（不进 LLM 上下文，仅供钩子读取），
`customType: "atelier:context-inject"`，`data: { agent: string } | null`。
**不要**误用 `CustomMessageEntry`（会进入 LLM 上下文，会被 compaction 压缩）。

钩子读取后通过 `appendEntry("atelier:context-inject", null)` 写空标记
实现一次性消费。下次 `before_agent_start` 扫描到空标记时 `break` 走默认逻辑。

### 4. 部署影响

- **无需迁移**：`~/.config/pi/agents/*.md` 的旧 symlink 自动失效但被
  `resolveAgentFile` / `resolve_agent_file` 多路径策略绕过。
  下次 `blue stow pi --restow` 会清理掉。
- **subagent-wrapper.sh 需重新部署**：`blue stow pi --restow`。
- **plugin 自身重启即可生效**：`blue rebuild` 后 pi 进程重启时
  atelier 重新加载（jiti + tsx 缓存）。

### 5. 兼容性矩阵

| 项                          | 0.1.0 | 0.1.1                            |
| --------------------------- | ----- | -------------------------------- |
| pi 扩展 API 最低版本        | 0.74+ | 0.74+                            |
| 运行时（pi 内置 Bun）       | —     | `bun:sqlite`（非 `node:sqlite`） |
| tmux 最低版本               | 3.0+  | 3.0+                             |
| schema 版本（atelier_runs） | v2    | v2（无变化）                     |

### 6. 已知问题

- `~/.config/pi/agents/` 下 7 个旧 symlink 仍存在但失效，不影响功能。
  建议 `rm -f ~/.config/pi/agents/*.md` 清理（stow 重新部署会自动
  移除）。
- `subagent` 工具的 `images` 字段在 parallel / chain 模式下未做透传
  （仅 single 模式支持），沿用 0.1.0 行为。

---

## 早期版本

### [0.1.0] - 2026-06-30

- INITIAL: bootstrap pi-atelier as standalone pi package
- tmux split subagent execution
- SQLite registry + orphan-recovery + stuck-detector
- checkpoint / resume / workflow 长程任务恢复
- CAPABILITY_SELF_CHECK + Return Header 协议

[0.2.0]: https://github.com/ShineBreaker/pi-atelier/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/ShineBreaker/pi-atelier/compare/162d0fe...v0.1.1
[0.1.0]: https://github.com/ShineBreaker/pi-atelier/releases/tag/v0.1.0
