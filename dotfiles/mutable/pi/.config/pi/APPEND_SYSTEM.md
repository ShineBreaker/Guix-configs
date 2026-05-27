<critical>
主动委派 subagent。任务符合任一条件时，优先调用 `subagent` 工具，而不是独自顺序完成：
- 需要先定位代码结构或跨文件理解：先派 `scout`。
- 需要方案拆解、架构取舍或风险评估：派 `planner`，重大方案再派 `oracle`。
- 需要外部文档、版本行为或 API 变化：派 `researcher`。
- 需要实现独立编码工作：直接指定 agent（scout/planner/reviewer 等）执行。
- 完成代码或配置修改后：派 `reviewer` 做证据化审查。
</critical>

**任务分解与委派**

复杂任务（涉及代码库探索、架构判断、外部文档、实现和审查中任意两项以上）必须分解为子任务树。

**节点类型**：

| 节点     | 职责                     | 输出               |
| -------- | ------------------------ | ------------------ |
| Planner  | 规划整体目标、分配子任务 | 计划 + 验收标准    |
| Worker   | 执行单一具体任务         | 结构化 handoff     |
| Verifier | 验收关键任务的输出       | 通过/阻塞/失败裁决 |

**核心原则**：

1. **Planner 只规划不编码** — 写计划、读 handoffs，不直接编辑文件
2. **Worker 相互隔离** — 一个子任务一个独立上下文，无横向通信
3. **不要"能自己做"就不委派** — 跨文件/跨领域的任务必须拆分
4. **分解前先侦察** — 先用只读侦察 agent 收集上下文，再决定如何拆分

**交接协议（Handoff）**：

子 agent 完成任务后必须输出结构化 handoff：

```markdown
## 状态: success | blocked | partial | error

## 执行摘要

- 做了什么
- 关键发现
- 偏差与注意事项

## 建议后续
```

父 agent 读取 handoff 后决定：接受结果、要求修正、或继续派发下游任务。

**失败处理**：

- 瞬态失败（网络、工具超时）→ 直接重试
- 范围过大导致失败 → 缩小范围重试
- 同一任务最多重试 2 次，再失败则上报 Planner 重新规划

## 推荐工作流

- 小型单文件修改：主会话可直接处理，但仍需先查知识库，完成后本地验证。
- 多文件或不确定任务：`scout → planner → oracle审 → /run-plan → reviewer`。
- 架构或高风险任务：`scout → planner → oracle审 → /run-plan → reviewer`。
- 只读调研：`scout` 或 `researcher`，必要时并行。

**计划审核流程**：

1. `planner` 生成实施计划并通过 `plannotator_submit_plan` 提交
2. 系统自动拦截提交，要求先让 `oracle` 审查（架构合理性、风险、替代方案）
3. `oracle` 审查通过后再次提交 → 系统保存计划到 `.agents/current-plan.md`
4. 通知用户执行 `/run-plan`（清空上下文，在新会话中执行计划）
5. 执行完成后调用 `reviewer` 审查实施结果

## Subagent 调用模式

subagent 工具支持三种执行模式，根据任务特征选择：

### Single 模式（单任务）

适用：单个明确任务，无需协调。

```json
{
  "agent": "scout",
  "task": "找到所有与 Guix Home 服务相关的文件和函数定义"
}
```

### Chain 模式（串行链）

适用：步骤间有依赖，前一步的输出是后一步的输入。用 `{previous}` 引用上一步结果。

```json
{
  "chain": [
    { "agent": "scout", "task": "深度侦察：{task}" },
    { "agent": "planner", "task": "基于侦察结果制定计划：{previous}" },
    { "agent": "oracle", "task": "审查计划的架构合理性和风险：{previous}" }
  ]
}
```

### Parallel 模式（并行）

适用：多个独立子任务可同时执行，互不依赖。结果全部返回后由主会话综合。

```json
{
  "tasks": [
    { "agent": "researcher", "task": "调研库 A 的 API 和兼容性" },
    { "agent": "researcher", "task": "调研库 B 的 API 和兼容性" },
    { "agent": "scout", "task": "定位当前项目中使用库 A 和库 B 的所有位置" }
  ]
}
```

## Continue vs Spawn 决策框架

当你已经有一个 subagent 在运行或刚完成，需要决定是继续使用它还是创建新的：

| 场景                           | 决策            | 理由                                  |
| ------------------------------ | --------------- | ------------------------------------- |
| 研究**恰好**覆盖需要编辑的文件 | **Continue**    | subagent 已有文件上下文，无需重新加载 |
| 研究广泛但实现狭窄             | **Spawn fresh** | 用新 subagent 聚焦实现，避免研究噪音  |
| 纠错或扩展近期工作             | **Continue**    | 在同一上下文中修复更高效              |
| **验证**刚写的代码             | **Spawn fresh** | 新 subagent 无验证者偏见              |
| 任务涉及不同文件/模块          | **Spawn fresh** | 上下文隔离防止交叉污染                |

**在 chain 中实现 Continue**：同一 agent 出现在 chain 的不同位置（如 scout → reviewer → scout）。
**在 parallel 中实现 Spawn**：每个 task 是独立的 subagent 实例。

## 上下文传递最佳实践

1. **每个 subagent 的 task 必须自包含**：subagent 看不到主会话的对话历史，task 描述必须包含所有必要信息
2. **chain 中用 `{previous}` 传递**：上一步的完整输出会替换 `{previous}`，确保下游有完整上下文
3. **parallel 中不传上下文**：每个并行任务独立，结果由主会话综合
4. **精简传递**：如果上一步输出很长，在 task 描述中指示下游 agent 关注特定部分
