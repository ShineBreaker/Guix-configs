# Bounded Task Schema — 设计草案（未实现）

> 来源：punkjazz.ai §03 "What a task carries" + Carlos E. Perez "bounded task · explicit identity · contemporaneous evidence · independent verification · safe recovery"。
>
> 状态：**设计草案，未实现**。明早用户拍板是否落地。

## 核心命题

**任务 = 持久对象，不是对话里的临时概念。** 现在 hermes 任务 = 对话上下文里的"这段"，完事就散。punkjazz 的架构是任务**有持久化表示**：identity / expectations / work-link / lifecycle。

## 当前痛点

1. **任务完成没有锚**：agent 报 success 之后，下次开新会话找不到"上次那个任务到底做了啥"
2. **跨会话回顾困难**：想知道 3 天前的任务 false-success 真命中了哪些 → 没法查
3. **correction funnel 没着落**：correction 写 KB，但任务本身不存，KB 卡片缺少锚
4. **任务状态机没有**：blocked / recovered / reopened 不可追溯

## 设计草案

### 1. 持久化层

```sql
-- SQLite + FTS5（hermes 已有 state.db 的同套栈）
CREATE TABLE bounded_tasks (
    id              TEXT PRIMARY KEY,        -- uuid / timestamp-based
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    closed_at       INTEGER,
    status          TEXT NOT NULL,           -- 'open' / 'closed' / 'reopened' / 'abandoned'
    title           TEXT NOT NULL,
    description     TEXT,

    -- punkjazz 4 元组
    expectations    TEXT,                    -- task-contract 全文 (false-success / evidence / verification / replan)
    work_link       TEXT,                    -- commit hash / branch / artifact path
    identity        TEXT,                    -- session_id / worktree path / branch name

    -- lifecycle 状态机
    lifecycle       TEXT,                    -- 'classify' / 'gate' / 'predict' / 'act' / 'assess' / 'verify' / 'close'
    replan_count    INTEGER DEFAULT 0,
    replan_max      INTEGER DEFAULT 2,

    -- evidence（hash + 描述 + 命令）
    evidence        TEXT,                    -- JSON array

    -- correction 关联
    correction_ids  TEXT,                    -- 关联的 KB 卡片 ids（correction funnel 输出）

    -- authority gate 决策记录
    authority_decisions TEXT,                -- JSON: [{action, requested_at, decided_at, user_choice}]
);
```

### 2. 工具接口

**新加 3 个 tool**（写代码 + hermes 注册）：

- `task_new(title, description, expectations, replan_max=2)` → task_id
- `task_close(task_id, evidence, status='success')`
- `task_reopen(task_id, finding, new_expectations=None)`
- `task_list(status=None, limit=20)` → list
- `task_get(task_id)` → full record

集成点：

- `task-contract` skill 触发时**自动 task_new**
- 任务收尾时**自动 task_close**
- `adversarial-review-trigger` 找到 finding 时**自动 task_reopen**
- `correction-funnel` 跑通时**自动写入 correction_ids**

### 3. 不在范围内（V1）

- ❌ 跨 hermes profile 同步（V2）
- ❌ 跨机器同步（V2）
- ❌ UI 面板（V2）
- ❌ 自动转 KB 卡片（已在 correction-funnel 里实现）

### 4. 成本估算

**写代码量**：
- SQLite schema + migration：~150 行 Python
- 3 个 tool 实现：~300 行 Python（每个 100 行）
- hermes toolsets 注册：~30 行
- 集成到 task-contract / correction-funnel / adversarial-review-trigger：~100 行
- 测试 + verify 脚本：~200 行

**总**：~800 行 Python，1-2 天工作量。

**风险**：
- hermes toolsets 注册流程需要查 AGENTS.md 确认 schema 格式
- SQLite schema migration 跟 hermes state.db 共存要考虑不破坏
- 用户审批门槛 —— 涉及 hermes 核心代码改动，不是 skill 改动

### 5. 替代方案（成本低）

**V0（替代）**：用 fact_store 模拟 + markdown 模板

- 在 fact_store 里给每个 task 一条 entry
- 用 markdown 模板生成 task-contract 持久化到 `~/.local/share/hermes/state/tasks/<task-id>.md`
- task-contract skill 触发时读 + 写
- 不需要改 hermes 代码

**V0 vs V1 评估**：
- V0：1-2 小时搞定，无侵入，但不能 query/状态机
- V1：1-2 天，但 queryable、可视化、可与 correction funnel 联动

## 拍板建议

**建议从 V0 起步**：先在 fact_store 里搭起 task 持久化的雏形，验证概念；V1 在 V0 用熟之后再做。

不**立**即实施的原因：
- 涉及 hermes 核心工具改动（写代码 + 编译 + 测试）
- 你明早过来 review，可能对设计有不同想法
- 当前 skill 套件已经覆盖了大部分 punkjazz 方法论，V1 是锦上添花

## 关联文档

- `references/example-graph-engineering-translation.md` — 真实 task-contract 样本
- punkjazz.ai §03 — "bounded task · explicit identity · contemporaneous evidence · independent verification · safe recovery"
- hermes-agent skill §"Durable & Background Systems" — 现有持久化层（kanban.db / state.db / cron）的实现

## 自包含性

本文件是 design doc，不是 skill。备份 `tar ~/.local/share/hermes/skills/hermes-agent-ops/agent-loop-topology/` 完整还原（在同一目录下）。

## Out of scope

- V1 实现（用户拍板后才做）
- V2 / 跨机器同步（未设计）
- 与 hermes StateDB 的整合细节（V1 启动时再讨论）