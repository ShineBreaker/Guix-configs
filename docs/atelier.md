# Atelier — Subagent 可视化执行平台

## §0 五层速览

| 层       | 组件                                 | 职责                                 |
| -------- | ------------------------------------ | ------------------------------------ |
| **调度** | `atelier run` / `atelier spawn`      | 接收 prompt，选 agent，启动 subagent |
| **执行** | `task` tool / `subagent-tool`        | 子进程管理，上下文注入，生命周期控制 |
| **注册** | `atelier-registry` (SQLite)          | subagent 实例索引、状态追踪、查询    |
| **恢复** | `orphan-recovery` / `stuck-detector` | 死进程检测、卡住检测、自动清理       |
| **观测** | `session-log` / `workfile`           | 执行日志、结构化数据持久化           |

## §1 设计原则

| #   | 原则           | 说明                                       |
| --- | -------------- | ------------------------------------------ |
| 1   | **透明性**     | subagent 执行过程对用户可见（pane / 日志） |
| 2   | **可恢复**     | 进程崩溃不丢状态，orphan 自动清理          |
| 3   | **最小权限**   | subagent 不继承父进程的 MCP 工具链         |
| 4   | **结构化输出** | 结果通过 workfile 传递，不依赖 stdout 解析 |
| 5   | **幂等注册**   | 同一 runId 重复注册不产生重复条目          |

## §2 节点类型与验证级别

### 2.1 节点类型

| 类型           | 说明                       | 典型用途                 |
| -------------- | -------------------------- | ------------------------ |
| `subagent`     | 标准子 agent 执行          | 代码生成、文件修改、研究 |
| `visual-agent` | 可视化 agent（带 UI pane） | 需要用户交互的任务       |
| `planner`      | 规划 agent                 | 复杂任务拆解             |
| `worker`       | 工作 agent                 | 具体执行单元             |

### 2.2 验证级别

| 级别       | 验证内容              | 失败行为         |
| ---------- | --------------------- | ---------------- |
| `none`     | 无验证                | 直接通过         |
| `basic`    | 输出非空              | 返回空结果错误   |
| `strict`   | 输出格式 + 语义完整性 | 返回验证失败错误 |
| `paranoid` | 全量校验 + 沙盒测试   | 返回详细错误报告 |

## §3 失败恢复策略

| 场景     | 检测方式                     | 恢复动作                              |
| -------- | ---------------------------- | ------------------------------------- |
| 进程崩溃 | PID 不存在 + workfile 未完成 | 标记为 `failed`，记录错误             |
| 进程卡住 | 超时无输出（stuck-detector） | 发送 SIGTERM，等待后 SIGKILL          |
| 孤儿进程 | 注册表有记录但无父进程       | 自动回收，标记为 `orphan-recovered`   |
| 输出异常 | workfile 解析失败            | 保留原始输出，标记为 `invalid-output` |

## §4 执行管线（五阶段）

```
prompt → [1] 路由选 agent → [2] 上下文注入 → [3] 启动 subagent
                                              ↓
                              [5] 结果回收 ← [4] 执行 + 日志记录
```

### 阶段详解

| #   | 阶段 | 组件               | 说明                                    |
| --- | ---- | ------------------ | --------------------------------------- |
| 1   | 路由 | `atelier run`      | 根据 prompt 内容选择 agent 类型         |
| 2   | 注入 | `context-injector` | 注入 AGENTS.md、skill、工作目录等上下文 |
| 3   | 启动 | `subagent-tool`    | `task` tool 创建子进程                  |
| 4   | 执行 | subagent 进程      | 实际执行任务，输出写入 workfile         |
| 5   | 回收 | `atelier-registry` | 解析 workfile，更新状态，返回结果       |

## §5 系统全景图

```
┌─────────────────────────────────────────────────┐
│                   用户请求                      │
└──────────────────────┬──────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────┐
│              atelier run / spawn                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │路由选择  │  │上下文注入│  │ 验证级别 │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
└───────┼─────────────┼─────────────┼─────────────┘
        ▼             ▼             ▼
┌─────────────────────────────────────────────────┐
│              subagent 进程                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ task tool│  │ workfile │  │ session  │       │
│  │          │  │  写入    │  │   log    │       │
│  └──────────┘  └──────────┘  └──────────┘       │
└──────────────────────┬──────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────┐
│              atelier-registry (SQLite)          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ 实例索引 │  │ 状态追踪 │  │ 查询 API │       │
│  └──────────┘  └──────────┘  └──────────┘       │
└──────────────────────┬──────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────┐
│              恢复层                             │
│  ┌───────────────┐  ┌──────────────┐            │
│  │orphan-recovery│  │stuck-detector│            │
│  └───────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────┘
```

## §6 文件清单

### 6.1 核心 TypeScript 文件

| 文件                  | 职责                                |
| --------------------- | ----------------------------------- |
| `atelier.ts`          | 主入口，`run` / `spawn` 命令        |
| `subagent-tool.ts`    | subagent 工具接口，`task` tool 封装 |
| `context-injector.ts` | 上下文注入（AGENTS.md、skill、cwd） |
| `session-log.ts`      | 执行日志记录与查询                  |
| `workfile.ts`         | workfile 读写、结构化数据持久化     |
| `registry.ts`         | SQLite 索引，实例注册/查询/状态更新 |
| `orphan-recovery.ts`  | 孤儿进程检测与回收                  |
| `stuck-detector.ts`   | 卡住检测（超时无输出）              |

### 6.2 辅助脚本

| 文件                 | 职责                              |
| -------------------- | --------------------------------- |
| `validate-output.ts` | 输出验证（basic/strict/paranoid） |
| `format-result.ts`   | 结果格式化                        |
| `cleanup.ts`         | 定期清理过期日志和 workfile       |

## §7 核心数据流

### 7.1 Subagent 工具全链路

```
用户: "改 dotfiles/enable/emacs/..."
  → atelier run (路由 → worker)
    → context-injector (注入 AGENTS.md + cwd)
      → subagent-tool (创建 task)
        → 子进程执行
          → workfile 写入结果
        ← registry 记录状态
      ← 格式化结果
    ← 返回用户
```

### 7.2 真相源分层

| 层  | 存储位置                      | 说明               |
| --- | ----------------------------- | ------------------ |
| L0  | subagent 进程内存             | 执行中的临时状态   |
| L1  | workfile (`.agents/workfile`) | 结构化输出，持久化 |
| L2  | session-log                   | 执行日志，可追溯   |
| L3  | registry (SQLite)             | 索引，可查询       |

### 7.3 runId 格式

```
<timestamp>-<agent>-<short-hash>
例: 20260625-143022-worker-a3f2
```

### 7.4 Workfile 兜底

当 subagent 进程异常退出时，workfile 是唯一的状态恢复源：

- 进程崩溃 → 检查 workfile 是否有部分输出
- 进程卡住 → 检查 workfile 最后写入时间
- 输出格式错误 → 保留原始 workfile 供人工检查

### 7.5 Session 日志

每次 subagent 执行生成一个 session 日志文件，包含：

- 启动参数（agent 类型、prompt、cwd）
- 执行时间线（开始、结束、耗时）
- 输出摘要（成功/失败、错误信息）
- 资源使用（内存、CPU 时间）

## §8 Public API

### 8.1 Subagent 工具接口

```typescript
interface SubagentTool {
  // 创建子 agent 执行任务
  create(params: {
    agent: string; // agent 类型
    prompt: string; // 任务描述
    cwd?: string; // 工作目录
    validation?: "none" | "basic" | "strict" | "paranoid";
    timeout?: number; // 超时（毫秒）
  }): Promise<SubagentResult>;

  // 查询子 agent 状态
  status(runId: string): Promise<SubagentStatus>;

  // 终止子 agent
  kill(runId: string): Promise<void>;
}
```

### 8.2 三种运行模式

| 模式          | 说明               | 适用场景                |
| ------------- | ------------------ | ----------------------- |
| `run`         | 同步执行，等待结果 | 简单任务，需要立即结果  |
| `spawn`       | 异步执行，后台运行 | 复杂任务，可稍后查询    |
| `interactive` | 交互式，用户可介入 | 需要人工确认/输入的任务 |

### 8.3 命令清单

| 命令                     | 说明         |
| ------------------------ | ------------ |
| `atelier run <prompt>`   | 同步执行任务 |
| `atelier spawn <prompt>` | 异步执行任务 |
| `atelier status <runId>` | 查询任务状态 |
| `atelier kill <runId>`   | 终止任务     |
| `atelier list`           | 列出所有任务 |
| `atelier cleanup`        | 清理过期任务 |

### 8.4 Plan Review Gate

复杂任务在执行前需要计划审核：

1. subagent 生成执行计划
2. 计划提交给用户/父 agent 审核
3. 审核通过后才执行
4. 审核拒绝则终止

### 8.5 Visual Agent 移交

当任务需要用户交互时：

1. 检测到交互需求（UI 操作、确认对话）
2. 自动切换到 `visual-agent` 类型
3. 创建可视化 pane
4. 用户在 pane 中完成交互
5. 结果回传给原 subagent

## §9 Atelier Registry

### 9.1 Schema

```sql
CREATE TABLE subagents (
  run_id TEXT PRIMARY KEY,
  agent_type TEXT NOT NULL,
  prompt TEXT,
  status TEXT DEFAULT 'pending',
  cwd TEXT,
  validation TEXT DEFAULT 'basic',
  created_at INTEGER,
  started_at INTEGER,
  completed_at INTEGER,
  error TEXT,
  output_path TEXT
);

CREATE INDEX idx_status ON subagents(status);
CREATE INDEX idx_agent_type ON subagents(agent_type);
CREATE INDEX idx_created ON subagents(created_at);
```

### 9.2 状态机

```
pending → running → completed
                  → failed
                  → killed
                  → orphan-recovered
```

### 9.3 启动流程

1. 检查 SQLite 文件是否存在
2. 不存在则创建 schema
3. 扫描现有 workfile 目录，补充注册
4. 启动 orphan-recovery 守护

### 9.4 公开 API

| 方法                          | 说明         |
| ----------------------------- | ------------ |
| `register(runId, meta)`       | 注册新实例   |
| `updateStatus(runId, status)` | 更新状态     |
| `get(runId)`                  | 查询单个实例 |
| `list(filter?)`               | 列出实例     |
| `cleanup(before?)`            | 清理过期实例 |

## §10 失败恢复与可观测性

### 10.1 Fallback 模型链

执行失败时的降级策略：

1. **重试**：相同 agent 重试一次
2. **降级**：切换到更简单的 agent 类型
3. **跳过**：标记失败，继续后续任务
4. **终止**：整个流程终止

### 10.2 waitForCompletion 异常路径

| 异常       | 处理                               |
| ---------- | ---------------------------------- |
| 超时       | 发送 SIGTERM，等待 5s，SIGKILL     |
| 进程不存在 | 检查 workfile，标记 failed         |
| 输出为空   | 检查 workfile 时间戳，可能还在写入 |

### 10.3 Pane 死亡检测

可视化 agent 的 pane 可能因用户关闭或进程崩溃死亡：

- 定期检查 pane 进程是否存活
- 死亡时回收资源，标记任务状态

### 10.4 Orphan Recovery

孤儿进程检测与回收：

- 定期扫描 registry 中 `running` 状态的实例
- 检查对应 PID 是否存活
- 不存活则标记为 `orphan-recovered`

### 10.5 Stuck Detection

卡住检测：

- 监控 workfile 最后修改时间
- 超过阈值（默认 5 分钟）无更新
- 发送 SIGTERM 尝试终止

### 10.6 Session 摘要

执行完成后生成摘要：

- 任务描述
- 执行时间
- 输出路径
- 成功/失败状态
- 错误信息（如有）

## §11 配置文件

### 11.1 settings.json atelier 段

```json
{
  "atelier": {
    "defaultValidation": "basic",
    "timeout": 300000,
    "stuckThreshold": 300000,
    "cleanupInterval": 3600000,
    "maxConcurrent": 5,
    "logDir": ".agents/sessions",
    "workfileDir": ".agents/workfile"
  }
}
```

### 11.2 agents/\*.md frontmatter

```yaml
---
name: worker
type: subagent
validation: basic
timeout: 300000
context:
  - AGENTS.md
  - .agents/skills/
---
```

### 11.3 prompts/\*.md 模板

模板用于上下文注入，支持变量替换：

- `{{cwd}}` — 工作目录
- `{{prompt}}` — 用户 prompt
- `{{agent}}` — agent 类型
- `{{skill}}` — 关联的 skill

### 11.4 路径解析一览

| 配置项         | 默认值               | 说明              |
| -------------- | -------------------- | ----------------- |
| `logDir`       | `.agents/sessions`   | session 日志目录  |
| `workfileDir`  | `.agents/workfile`   | workfile 目录     |
| `registryPath` | `.agents/atelier.db` | SQLite 数据库路径 |

## §12 故障排查

### 常见问题

| 问题               | 原因               | 解决                      |
| ------------------ | ------------------ | ------------------------- |
| subagent 启动失败  | agent 类型不存在   | 检查 agents/\*.md 配置    |
| 输出为空           | prompt 过于模糊    | 重写 prompt，增加具体指令 |
| 状态一直是 pending | 调度器未运行       | 检查 atelier 进程         |
| orphan 大量积累    | 父进程异常退出     | 手动 `atelier cleanup`    |
| workfile 解析失败  | 输出格式不符合预期 | 检查 validation 级别设置  |

### 调试命令

```bash
# 查看所有任务状态
atelier list

# 查看特定任务详情
atelier status <runId>

# 手动触发清理
atelier cleanup

# 查看 registry 数据库
sqlite3 .agents/atelier.db "SELECT * FROM subagents ORDER BY created_at DESC LIMIT 10;"
```

## §13 与 agenote 的协同

### 协同点

| 场景                  | 机制                                  |
| --------------------- | ------------------------------------- |
| subagent 执行经验记录 | subagent 完成后自动调用 `agenote_add` |
| 执行前经验查询        | context-injector 注入相关 KB 卡片     |
| 失败经验沉淀          | 失败任务自动记录 mistake 卡片         |
| 工作流模式提取        | 定期扫描 session-log，提取高频模式    |

### 数据流

```
subagent 执行
  ↓ 成功
  → agenote_add (note 卡片)
  ↓ 失败
  → agenote_add (mistake 卡片)

context-injector
  ← agenote_search (查询相关经验)
```

## §14 已知不变量与未做项

### 不变量

1. subagent 不继承父进程的 MCP 工具链（最小权限）
2. workfile 是唯一的状态恢复源（进程崩溃后）
3. registry 使用 SQLite，不依赖外部数据库
4. 所有 subagent 执行必须有 runId

### 未做项

| 项目       | 说明                     | 优先级 |
| ---------- | ------------------------ | ------ |
| 并发限制   | 最大同时运行 subagent 数 | 中     |
| 优先级队列 | 任务优先级调度           | 低     |
| 资源限制   | 内存/CPU 使用限制        | 低     |
| 分布式执行 | 多机 subagent 执行       | 低     |

## §15 命令速查表

| 命令              | 说明     | 示例                                         |
| ----------------- | -------- | -------------------------------------------- |
| `atelier run`     | 同步执行 | `atelier run "改 dotfiles"`                  |
| `atelier spawn`   | 异步执行 | `atelier spawn "研究 API"`                   |
| `atelier status`  | 查看状态 | `atelier status 20260625-143022-worker-a3f2` |
| `atelier kill`    | 终止任务 | `atelier kill <runId>`                       |
| `atelier list`    | 列出任务 | `atelier list --status running`              |
| `atelier cleanup` | 清理过期 | `atelier cleanup --before 20260624`          |

## §16 错误码速查

| 错误码             | 说明             | 处理                       |
| ------------------ | ---------------- | -------------------------- |
| `AGENT_NOT_FOUND`  | agent 类型不存在 | 检查 agents/\*.md          |
| `TIMEOUT`          | 执行超时         | 增加 timeout 或重试        |
| `INVALID_OUTPUT`   | 输出格式错误     | 检查 validation 级别       |
| `ORPHAN_RECOVERED` | 孤儿进程被回收   | 检查父进程是否异常         |
| `STUCK_DETECTED`   | 进程卡住被终止   | 检查任务是否需要人工交互   |
| `WORKFILE_MISSING` | workfile 不存在  | 检查 subagent 是否正常写入 |

## 附录

### A. 设计决策溯源

| 决策                  | 理由                     | 替代方案                                    |
| --------------------- | ------------------------ | ------------------------------------------- |
| SQLite 作为 registry  | 零依赖、单文件、足够性能 | PostgreSQL（过重）、JSON 文件（并发不安全） |
| workfile 作为输出通道 | 结构化、可持久化、可追溯 | stdout（不可靠）、数据库（过重）            |
| PID 检测作为存活判断  | 简单可靠、跨平台         | 进程间通信（复杂）、心跳（有延迟）          |

### B. 工作流分析

标准 subagent 执行流程：

1. 用户请求 → atelier 路由
2. 上下文注入（AGENTS.md、skill、cwd）
3. 启动 subagent（task tool）
4. subagent 执行 + 写入 workfile
5. 结果回收 + 状态更新
6. 返回用户

### C. MiMoCode 映射表

| Atelier 概念    | MiMoCode 对应   |
| --------------- | --------------- |
| subagent        | actor           |
| workfile        | result file     |
| registry        | actor registry  |
| session-log     | execution log   |
| orphan-recovery | actor cleanup   |
| stuck-detector  | timeout handler |

### D. 配置示例

```json
{
  "atelier": {
    "defaultValidation": "basic",
    "timeout": 300000,
    "stuckThreshold": 300000,
    "cleanupInterval": 3600000,
    "maxConcurrent": 5,
    "logDir": ".agents/sessions",
    "workfileDir": ".agents/workfile"
  }
}
```
