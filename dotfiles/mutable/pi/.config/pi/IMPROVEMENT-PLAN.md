# Pi Agent 体系改进计划

基于 `agent-architecture.md`（Claude Code Agent 架构文档）对当前 Pi agent 体系的差距分析与改进方案。

> **状态**：已通过 planner 审查，根据反馈修正了 3 处关键决策。

## 现状分析

### 当前 Agent 阵容

| Agent    | 模型                    | 思考级别 | 工具                             | 职责                 |
| -------- | ----------------------- | -------- | -------------------------------- | -------------------- |
| scout    | deepseek/deepseek-v4-flash | low    | read, grep, find, ls             | 快速只读侦察         |
| planner  | zai/GLM-5.1             | —        | read, grep, find, ls             | 战略规划             |
| worker   | zai/GLM-5.1             | —        | read, grep, find, ls, bash, edit, write | 深度编码执行 |
| reviewer | zai/GLM-5.1             | —        | read, grep, find, ls, bash, write | 代码审查 + 报告输出  |
| oracle   | zai/GLM-5.1             | —        | read, grep, find, ls             | 架构顾问             |
| researcher | deepseek/deepseek-v4-pro | medium | read, grep, find, ls, bash       | 文档检索调研         |

### 当前 Prompt 模板

| 模板                    | 链路                                           |
| ----------------------- | ---------------------------------------------- |
| scout-and-plan          | scout → planner                                |
| implement               | scout(thorough) → planner → worker → reviewer  |
| implement-and-review    | worker → reviewer → worker(fix)                |
| design-review-implement | scout(thorough) → planner → oracle → worker → reviewer |

---

## 差距分析（Architecture Doc vs. 当前配置）

### 差距 1：缺少专用验证 Agent

**架构文档**：Verification Agent 是对抗性验证者——它**实际运行命令**验证实现是否正确，且明确防范两个失败模式：
1. 验证回避（找理由不运行检查）
2. 被"前 80%"诱惑（看到精美 UI 就倾向通过）

**当前**：reviewer 兼任了代码审查和验证两个角色，但重点偏向静态代码审查。缺少对抗性验证思维。

**改进**：增强现有 reviewer 的验证能力，加入对抗性验证指令，而不是新增独立 verifier agent（避免 agent 数量膨胀）。

### 差距 2：Scout 缺少 bash 工具

**架构文档**：Explore Agent 允许 `BashTool`（只读模式，用于 `ls`, `git status`, `git log` 等）

**当前**：scout 只有 `read, grep, find, ls`，无法运行 `git log`、`git diff` 等只读 bash 命令。

**改进**：给 scout 添加 `bash` 工具，但在系统提示中限定只读使用。

### 差距 3：缺少并行执行 Prompt 模板

**架构文档**：Coordinator 模式强调"并行性是超级力量"——独立任务同时运行。

**当前**：所有 prompt 模板都是串行 chain，没有 parallel 模式的 prompt。

**改进**：添加并行模式的 prompt 模板。

### 差距 4：Agent 模型分配不够精细

**架构文档**：
- Explore Agent: `inherit` (ant) / `haiku` (external) — 用轻量模型
- Plan Agent: `inherit` — 继承
- Verification Agent: `inherit` — 继承
- General Purpose: `inherit` — 继承

**当前**：
- scout: deepseek-v4-flash (轻量，好)
- planner/oracle/worker/reviewer: 全部 GLM-5.1 (统一)
- researcher: deepseek-v4-pro (中等)

**改进**：根据任务复杂度调整模型分配。planner 和 oracle 需要强推理，保持 GLM-5.1；reviewer 需要细致分析，也可以保持。但 researcher 可以考虑用更轻量的模型。

### 差距 5：缺少 `maxTurns` 控制

**架构文档**：Agent 定义有 `maxTurns` 字段限制最大轮次。

**当前**：所有 agent 都没有 `maxTurns`，依赖全局超时 `timeoutMs: 1800000`。

**改进**：为轻量 agent（scout）添加 `maxTurns` 限制，防止过度探索。但 Pi 的 frontmatter 可能不支持此字段——需要确认。如果不支持，在系统提示中加入自限指令。

### 差距 6：Reviewer 输出写入固定路径可能冲突

**架构文档**：Verification Agent 可写临时测试脚本到 `/tmp`，不修改项目文件。

**当前**：reviewer 写入 `./.agents/{project-name}-review.md`，这个路径可能不存在且与其他工具的目录冲突。

**改进**：改为更安全的输出策略——直接在 handoff 文本中输出审查结果，不写入文件。或者使用 `/tmp` 路径。

### 差距 7：Handoff 协议不统一

**架构文档**：Handoff 分类器自动分类 handoff 类型，有结构化的上下文继承。

**当前**：各 agent 的输出格式各不相同（scout 是侦察摘要、worker 是详细 handoff、reviewer 是审查报告、oracle 是顾问意见）。虽然格式差异是合理的（不同角色不同输出），但核心 handoff 字段（Status、Summary、Follow-ups）应统一。

**改进**：统一各 agent 输出的核心 handoff 字段，保持各 agent 特有格式的扩展性。

### 差距 8：APPEND_SYSTEM.md 缺少并行委派的具体指导

**当前**：APPEND_SYSTEM.md 提到了委派原则，但没有给出具体的并行委派示例和判断标准。

**改进**：增加并行委派的决策矩阵和示例。

---

## 改进方案

### 改动 1：增强 reviewer — 融入对抗性验证能力

**文件**：`agents/reviewer.md`

**变更内容**：
- 在审查流程中增加"对抗性验证"步骤
- 加入架构文档中 Verification Agent 的两个失败模式警告（验证回避 + 被前80%诱惑）
- 按变更类型提供验证策略模板（前端/后端/CLI/基础设施/库/Bug修复/数据库）
- 统一 Verification 级别判定标准（与 worker 的 Verification 级别对齐）
- **保留 `write` 工具，限定只写 `/tmp`**：对抗性验证需要写临时验证脚本（这是 write 的合理用途）；不再写入 `./.agents/` 项目路径
- 审查报告改为 handoff 文本输出（不再写入项目文件），临时验证脚本写入 `/tmp`

### 改动 2：增强 scout — 添加 bash 只读能力

**文件**：`agents/scout.md`

**变更内容**：
- 工具列表添加 `bash`
- 在系统提示中明确限定 bash 只用于只读操作（git log、git diff、wc、head 等）
- 保持其他部分不变

### 改动 3：新增并行 Prompt 模板

**文件**：新增 `prompts/parallel-research.md`

**变更内容**：
- 提供 parallel 模式的 prompt 模板
- 示例：多方向并行调研后汇总

### 改动 4：新增研究-实施 Prompt 模板

**文件**：新增 `prompts/research-and-implement.md`

**变更内容**：
- researcher → planner → worker → reviewer 链
- 用于需要外部文档支撑的实施任务

### 改动 5：统一 Handoff 核心字段

**涉及文件**：所有 agent 定义

**变更内容**：
- 所有 agent 输出顶部统一包含：`## 状态`、`## 执行摘要`、`## 建议后续`
- 各 agent 在统一字段之后保持各自的扩展格式
- 这是最小化变更——只在需要的地方添加缺失字段

### 改动 6：增强 APPEND_SYSTEM.md

**文件**：`APPEND_SYSTEM.md`

**变更内容**：
- 增加并行委派的决策矩阵
- 增加具体的 subagent tool 调用示例（single / parallel / chain 三种模式的 JSON）
- 增加 **Continue vs Spawn 决策框架**（来自 Coordinator 模式）：
  - 研究恰好覆盖需要编辑的文件 → Continue（继续同一 worker）
  - 研究广泛但实现狭窄 → Spawn fresh（新建 worker）
  - 纠错或扩展近期工作 → Continue
  - 验证刚写的代码 → Spawn fresh（避免验证者偏见）
- 增加上下文传递最佳实践

### ~~改动 7~~：模型分配保持现状

**决策**：根据 planner 审查建议，**移除此改动**。

**理由**：
- researcher 的核心职责不仅是搜索，还包括评估来源可靠性、追踪版本差异、综合矛盾信息——这些需要较强推理
- deepseek-v4-pro 成本本身较低，降级到 flash 的节省有限但质量风险不可忽略
- 保持 `deepseek/deepseek-v4-pro` + `thinking: medium` 不变

---

## 改动优先级排序

| 优先级 | 改动                                   | 影响范围 | 风险 | 工作量 |
| ------ | -------------------------------------- | -------- | ---- | ------ |
| P0     | 改动 1：增强 reviewer 对抗性验证（保留 write 限定 /tmp） | reviewer | 低   | 中     |
| P0     | 改动 2：增强 scout bash 只读能力       | scout    | 低   | 小     |
| P1     | 改动 6：增强 APPEND_SYSTEM.md（含 Continue vs Spawn 框架） | 主会话 | 低 | 中   |
| P1     | 改动 3：新增 parallel-research prompt  | prompts  | 无   | 小     |
| P2     | 改动 5：统一 Handoff 核心字段          | 所有 agent | 低 | 小     |
| P2     | 改动 4：新增 research-and-implement prompt | prompts | 无  | 小     |

---

## 不做的改动（及理由）

1. **不新增独立 verifier agent**：避免 agent 数量膨胀。将对抗性验证能力融入 reviewer，通过系统提示区分"审查模式"和"验证模式"。
2. **不调整 worker 的模型**：GLM-5.1 是当前最强的编码模型，worker 需要强推理。
3. **不添加 `maxTurns` 字段**：Pi 的 agent frontmatter 不支持此字段。改为在系统提示中加入自限指令。
4. **不修改 tmux-subagents 扩展**：扩展代码本身运行良好，改进集中在 agent 定义层面。
5. **不降级 researcher 模型**：researcher 需要较强的推理能力来评估来源、综合矛盾信息，保持 deepseek-v4-pro。

## 后续优化（不阻塞本次改进）

1. **Scout 的 globalContext token 开销**：当前 scout 每次加载完整的 AGENTS.md + globalContext，对 quick 级别任务是不必要的开销。但 Pi 的 agent frontmatter 不提供 `omitGlobalContext` 字段。作为后续优化记录，等 Pi 支持后实施。
