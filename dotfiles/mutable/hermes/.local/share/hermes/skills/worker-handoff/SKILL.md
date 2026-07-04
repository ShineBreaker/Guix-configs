---
name: worker-handoff
description: 子任务派发规范 —— 定义 hermes 主会话如何把任务拆给 delegate_task 子 agent,以及子 agent 应如何产出标准化的 handoff 报告。适合在需要把大任务并行化、或需要独立验证的子任务时加载使用。
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [delegation, subagent, handoff, parallel-tasks, worker]
    related_skills: [task-planner, codebase-scout, code-reviewer]
---

# worker-handoff — 子任务派发与 handoff 规范

这个 skill 不是给主 agent 自己用的工作流,而是**给主会话派发子 agent 时的统一规范**。

加载本 skill 后,你应当按以下规范来:

1. **规划任务边界** —— 把任务拆成 N 个独立可并行的子任务
2. **派发** —— 用 `delegate_task` 派给子 agent,在 `context` 里附上下方的"Worker 行为规范"和具体的 Handoff 模板
3. **消费 handoff** —— 子 agent 完成后,按 Handoff 阅读指南评估是否信任、是否需要重试、是否串到下一步

---

## 派发模式

### 何时用 worker

- 需要跨文件或多模块的实现
- 需要可独立验证的 bug 修复(含回归测试)
- 计划已就绪、剩下的是机械实施
- 大型重构(worker 会自主处理依赖追踪和测试)

### 并发 vs 串行

| 场景       | 模式                                   |
| ---------- | -------------------------------------- |
| 独立子任务 | 用 `delegate_task(tasks=[...])` 并行派 |
| 链式任务   | A 完成后根据其 handoff 再派 B          |
| 大任务     | 先 task-planner 拆解,再批量派 worker   |

---

## Worker 行为规范(嵌入到子 agent 的 context)

子 agent 收到任务后,按以下规范工作:

### 工作风格(深度、自主、原则驱动)

- **目标导向**:接收的是"要什么",不是"怎么做"。自己找出最佳路径
- **多文件推理**:变更往往跨多个文件 —— 理解依赖关系,不要只看一个文件
- **最小化变更**:只改必须改的地方,避免无关重构
- **测试验证**:实施后用 `terminal` 跑测试、lint、类型检查
- **不留尾巴**:不留下 TODO、占位符、"以后再处理"的代码
- **诚实**:做不到的就标 blocked,不要假装完成

### 自主工作原则

1. **先理解,再动手**:阅读上下文、计划、相关文件
2. **将方向视为契约**:planner 给出的计划视为契约,根据实际代码验证它,但不默默做新的架构决策
3. **如果发现计划有缺口**:在输出中**标注风险**,由调用方决策,不要静默修补
4. **如果揭示了未批准的架构选择**:在输出中**标注并暂停**,等待调用方回复
5. **验证每一步**:编辑后读取文件确认变更正确,跑相关测试

### 编码规范

- 遵循项目现有风格和约定
- 命名保持一致性
- 错误处理:不吞异常,除非明确需要
- 不加推测性脚手架或"未来防护"
- 新增代码必须可测试;难以测试就 reconsider 设计
- 新增/修改功能必须更新对应文档(README / 注释 / CHANGELOG)
- 测试覆盖:新增代码应有对应测试,验证结果中标注

### Quality Floor

- 无占位 TODO,每个公共函数必须有真实实现
- 无 `throw new Error("not implemented")`,除非在明确断言辅助函数中
- 只注释非显而易见的 _why_,不写叙述性注释
- UI/交互 bug:必须截屏或录屏作为修复证据,在 handoff 中注明产物路径

### Verification 级别(自评)

| 级别                 | 含义                                               | 主会话响应              |
| -------------------- | -------------------------------------------------- | ----------------------- |
| `live-ui-verified`   | 实际复现 bug 并确认修复消除(真实浏览器/二进制/CLI) | 信任为已发布            |
| `unit-test-verified` | 目标测试覆盖变更路径并通过,无实际复现              | 非 UI bug 可接受        |
| `type-check-only`    | 仅类型检查/构建通过,无测试或复现                   | 弱,仅适合纯类型变更     |
| `not-verified`       | 未端到端验证(如纯重构,或环境阻塞)                  | 需要 code-reviewer 复审 |

### 何时不自行处理(必须暂停并报告)

1. 计划中的某个假设在实际代码中不成立
2. 实施揭示了需要产品/架构决策的新选择
3. 变更范围显著超出原计划
4. 需要修改配置文件、CI/CD 或其他基础设施

这些情况需要回到 task-planner 或 architecture-advisor 重新评估。

---

## Handoff 输出模板(子 agent 必须按此格式返回)

```markdown
## Status

success | partial | blocked

## 执行摘要

- 高层摘要,按文件列出如有用

## Branch

`<实际分支名>` (或 "(no branch)" 如果没有代码产出)

## What I did

- 高层摘要,按文件列出如有用

## Measurements

- <metric>: <before> <op> <after>

每行格式:`<指标名>: <之前> <op> <之后>`,op 为 `→` / `<=` / `<` / `>` / `>=` / `==` 之一。如果没有定量标准,写 `(none)`。

## Verification

live-ui-verified | unit-test-verified | type-check-only | not-verified

## 实施报告

### 完成内容

一句话总结做了什么。

### 变更文件

| 文件              | 变更类型 | 摘要         |
| ----------------- | -------- | ------------ |
| `path/to/file.ts` | 修改     | 做了什么修改 |
| `path/to/new.ts`  | 新增     | 用途         |

### 文档更新

- 更新了哪些文档(README / 注释 / CHANGELOG)

### 关键决策

- **决策 X**:为什么选择方案 A 而不是 B(如果存在选择)
- **决策 Y**:如何处理某边界条件

### 验证结果

- ✅ 测试通过:`npm test` — 结果(覆盖率:X%)
- ✅ 类型检查:`tsc --noEmit` — 结果
- ✅ Lint 通过:`eslint ...` — 结果

## Notes, concerns, deviations, findings, thoughts, feedback

- 任何规划者需要知道的信息:假设、意外、决策、不变量破坏、不清楚的需求、对任务范围的看法

## 建议后续

- 规划者应考虑发布的后续任务

## 遗留风险/问题

- ⚠️ [风险描述] — 建议后续处理
```

---

## Handoff 阅读指南(主会话消费时)

对于每个 worker 返回的 handoff:

1. **Status** 非 `success`:决定重试、修复还是澄清
2. **Branch**:记录它;如果另一个任务需要在此基础上构建,引用它
3. **What I did**:视为事实,但浏览是否有不符合预期的声明
4. **Verification**:基于此级别决定是否信任结果 —— `not-verified` 必须送 code-reviewer
5. **Measurements**:验证声称的量化指标是否真的在 git/文件系统里能看到
6. **Notes / concerns / deviations / findings**:最丰富的部分,每条都可能成为新任务
7. **Suggested follow-ups**:候选任务,接受、拒绝或合并

## 失败恢复策略(主会话决策)

当 worker 返回 `Status: blocked` 或失败时,根据失败模式决定:

| 失败模式          | 策略                                                           |
| ----------------- | -------------------------------------------------------------- |
| `cap-hit` / `oom` | 缩小范围重试:拆分更窄的任务、更紧的 toolsets、更精简的 context |
| `network-drop`    | 原样重试,视为瞬时故障                                          |
| `tool-error`      | 换模型重试                                                     |
| `unknown`         | 原样重试一次,再失败则放弃                                      |

同一任务重试 2 次后,优先放弃(从计划中删除,围绕它重新规划)而不是第 3 次尝试,除非有具体证据表明下次会成功。

---

## 在 hermes 里如何派发

### 单 worker 派发

```python
delegate_task(
  goal="<具体目标>",
  context="""worker 行为规范 + handoff 模板(如上) + 任务专属约束""",
  toolsets=['coding']  # 或具体子集
)
```

### 并行多 worker 派发

```python
delegate_task(tasks=[
  {"goal": "子任务 A", "context": "...", "toolsets": ["coding"]},
  {"goal": "子任务 B", "context": "...", "toolsets": ["coding"]},
])
```

每个子任务应该**目录不重叠**或**明确不冲突**,否则会打架。

## 重要规则

1. **可执行原则**:worker 看完你的目标不需要问"这里怎么做"
2. **每个 worker 必须有明确的 scope**:范围模糊的 worker 会到处乱改
3. **handoff 必读**:Status 不是 success 必须看 Notes
4. **Verification 不达标必送审**:`type-check-only` 和 `not-verified` 必须送 code-reviewer
5. **失败重试预算**:同一任务最多重试 2 次,第 3 次之前先 re-plan
