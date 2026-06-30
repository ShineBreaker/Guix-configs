# atelier — Subagent 可视化执行平台

基于 tmux 分屏的 subagent 执行扩展。通过 `subagent` 工具或 `/agentname` 快捷命令启动子 agent，在 tmux pane 内可视化执行，结果通过 workfile + result.md 结构化回收。

设计文档：`docs/atelier.md`（仓库根）。

## 目录结构

<!-- structor:begin -->

<!-- 此树形目录由 structor 自动生成，请勿手动编辑。 -->

```
atelier/
├── core/
│   ├── config.ts
│   ├── context.ts
│   ├── discovery.ts
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
│   ├── formatting.ts
│   ├── launcher.ts
│   ├── monitor.ts
│   ├── runner.ts
│   ├── session-log.ts
│   └── workfile.ts
└── index.ts
```

<!-- /structor -->

## 按职能分层

依赖方向无环：`core` ← `runtime` / `registry` / `lifecycle` ← `index`。

| 目录          | 职责                                  | 关键文件                                                              |
| ------------- | ------------------------------------- | --------------------------------------------------------------------- |
| `core/`       | 配置/类型/发现（无外部循环依赖）       | `types.ts`（接口 + DEFAULT_CONFIG）、`config.ts`、`discovery.ts`、`schemas.ts`、`context.ts`、`system-agents.ts` |
| `runtime/`    | 执行链路（tmux → 监控 → 编排）         | `launcher.ts`（tmux 分屏）、`monitor.ts`（轮询 + return-header 解析）、`runner.ts`（runChain/Parallel/Fallback）、`workfile.ts`、`session-log.ts`、`formatting.ts` |
| `registry/`   | 状态索引与治理（SQLite + 恢复层）      | `registry.ts`（SQLite 全局索引）、`orphan-recovery.ts`、`stuck-detector.ts`、`return-header.ts`、`completion-gate.ts` |
| `lifecycle/`  | 长程任务生命周期                       | `checkpoint.ts`（跨崩溃 checkpoint）、`workflow.ts`（可视化 workflow）、`resume.ts`（续跳） |

## 执行管线

```
subagent({...}) / /agentname
  → index.ts execute()        模式分流 + worker-single 警告
  → runner.ts                 executeWithFallback / runChain / runParallelBatches
  → launcher.ts launchSingle  生成 runId → 写 status.json{running} → tmux split-window
  → wrapper.sh (外部 pane)    pi --mode json → extract-pi-result.py → 写 result.md + status.json{completed}
  → monitor.ts waitForCompletion  轮询 status.json → 解析 Return Header → 同步 registry
  → workfile.ts ensureWorkfile     兜底持久化（agent 未自写时）
```

**runId 格式**（`runtime/launcher.ts` generateRunId）：`sa-{base36ts}-{3bytehex}`，例 `sa-ltj3m2x0-a1b2c3`。系统子 agent 用 `sys-` 前缀（`core/system-agents.ts` generateSystemRunId）。

**run 目录**（`$XDG_CACHE_HOME/pi/subagents/{runId}/`）：`task.md`、`status.json`、`subagent-prompt.md`（注入了 CAPABILITY_SELF_CHECK + RETURN_FORMAT_INSTRUCTION）、`result.md`、`stderr.log`。

## Registry / 持久化层

- **status.json 是 single source of truth**；SQLite registry（`$XDG_DATA_HOME/pi/atelier-registry.db`）是查询视图，崩溃可丢（删 .db 下次启动 `rebuildFromStatusFiles` 自动重建）。
- 用 Node 22+ 内置 `node:sqlite`（实验性，pi 启动时压制 ExperimentalWarning），零新依赖。
- 启动三步（best-effort，不阻塞扩展加载）：`rebuildFromStatusFiles` → `orphanRecovery` → `startStuckDetector`（后台 fiber，`unref` 不阻塞退出）。
- schema 演进：`SCHEMA_VERSION` + `migrate()`（`PRAGMA user_version` + `ALTER TABLE ADD COLUMN`）。

## 长程任务恢复（checkpoint / workflow / resume）

- `runChain` 每完成一步写 **checkpoint**（`lifecycle/checkpoint.ts`，跨崩溃恢复用）+ **workflow**（`lifecycle/workflow.ts`，可视化查看用）。两者同存于 `.agents/workflows/`：checkpoint 文件名 `{parentRunId}.json`（`sa-` 前缀），workflow 文件名 `{wf-id}.json`（`wf-` 前缀）。
- `listWorkflows` 只列 `wf-` 前缀文件，避免 checkpoint 被误判为 corrupt。
- `/atelier-resume <parentRunId>`：读 checkpoint → 把剩余 step 转 chainEntries → 调 `runChain` 真实 dispatch。**续跳会生成新的 parentRunId**（原 checkpoint 作历史保留）；崩溃前的 `{previous}` 用 `inheritedContextSnapshot`（前 2000 字）近似替换——这是设计内的降级。

## Return Header 协议

子 agent 在 final message 顶部写 `**Status**: success|partial|failed|blocked` + `**Summary**:`，由 `registry/return-header.ts` 结构化解析后写入 registry。指令通过 `launcher.ts prepareAgentPrompt` 注入 `subagent-prompt.md`。LLM 不写则降级为 `return_status:"unknown"`。

## 修改约束

- **外部脚本** `subagent-wrapper.sh` / `extract-pi-result.py` 在 `stow/pi/.local/share/pi/scripts/`（atelier 目录外），改它们走 stow 路径。它们只写 status.json/result.md，不知 SQLite 存在——atelier 是唯一的 SQLite writer。
- **completion-gate.ts** 的 `isTaskToolAvailable()` 当前恒 false（pi 无 task 工具），`decide()` 是 no-op。架构保留待 pi 接入 task 工具后激活，不要误删。
- **CAPABILITY_SELF_CHECK**（`runtime/launcher.ts`）硬注入所有 subagent prompt——设计决策，所有 subagent 无条件获得能力自检。
- 语法验证（容器无 tsc）：`host-spawn -- node --experimental-strip-types --check <file.ts>`（host node v22，类型剥离语法校验，抓语法/import 错误但不抓类型错误）。最终运行回归靠 `blue rebuild` + 跑 pi。
- **禁止 AI agent 自行 `blue rebuild` / `guix system reconfigure`**（见仓库根 AGENTS.md）。
