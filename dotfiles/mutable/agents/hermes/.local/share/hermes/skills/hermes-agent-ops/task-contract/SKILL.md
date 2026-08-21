---
name: task-contract
description: "在开始一个复杂或长期任务前，强制写下 task-contract（false-success conditions / expected evidence / verification approach / replan budget），让 verifier 后续有依据证伪完工声明。触发词：'开始一个复杂任务前 / task contract / 写任务契约 / false-success / 怕任务看起来做完但其实没 / 任务开始前先对齐'，或当用户给的任务**满足以下任一条件**：跨多个文件 / 涉及不可逆动作 / 可能多任务并行 / 长期任务 / 用户说'怕出岔子' / 任务有验收标准。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [task-contract, false-success, verification, planning, safety]
    related_skills: [task-planner, worker-handoff, code-reviewer, authority-gate, correction-funnel]
---

# task-contract — 任务开始前的契约

来源方法论：`Graph Engineering`（punkjazz.ai §03 "What a task carries"）和 `Loop Engineering`（Carlos E. Perez §"What good loop engineering actually is"）。

## 核心命题

**任务开始前的契约 = 任务结束时的 verifier**。没写契约就开干，等于让 agent 自己当 verifier —— 而 agent 没法证伪自己刚做的结论（"独立性是 loop engineering 最容易伪造的属性"）。

## 何时使用（trigger）

满足以下**任一**条件时，**必须**用本 skill：

- 任务跨多个文件或多个组件
- 任务涉及**不可逆动作**（部署、付费、删除、公开）
- 任务可能**多任务并行**（delegate / 并发 / 多 writer 同一 source tree）
- 任务**长期**（>5 步 / 跨会话 / 长期运行）
- 任务**有验收标准**但用户没显式声明（隐含需要）
- 任务**之前失败过**或用户说"怕出岔子"
- 用户**显式调用**本 skill

不适用：

- 单文件 README 修改、查询类、闲聊类
- 用户已经给了**明确的 success criteria**（写在用户消息里，且完整）

## 工作流程（4 步）

### Step 1: 复制模板

`cp ~/.local/share/hermes/skills/hermes-agent-ops/task-contract/templates/contract.md /tmp/contract-<task-id>.md`

或者直接按下方模板填到 `todo` 工具的 notes 字段。

### Step 2: 填空（4 个必填段）

#### A. false-success conditions（最容易漏的一栏）

问自己：**什么情况下，这个任务会"看起来成功但其实没做好"**？

最少列 3 条。常见模式：

| 模式 | 例子 |
|------|------|
| 报告无 artifact | "任务说做完了，但磁盘上没有 working artifact" |
| 测试绿但断言改了 | "测试套件绿，但 success criteria 被偷偷改了" |
| workspace 干净但 activity record 丢了 | "git status 干净，但 commit log 看不到做过的痕迹" |
| 跑通 happy path 但 boundary case 漏 | "测试通过，但只测了单一场景" |
| 多个子任务部分完成 | "主任务说 success，但 3 个子任务里 1 个 blocked 被忽略" |
| 用了错误的 verifier | "用同样的 reviewer agent 复核 worker agent → 同盲点" |

#### B. expected evidence

任务完成时**必须能拿出来**的 evidence 清单：

- 跑了哪些验证（命令 + 结果）
- 改了哪些文件（路径）
- 留了哪些日志 / 截图 / artifact 路径
- 谁 / 什么做了独立复核

#### C. verification approach（按 Perez ladder 分层）

| 层 | 用什么 | 紧度 |
|----|--------|------|
| 静态（formatter / linter / type-check） | 自动 | 紧 |
| 行为（单元 / 集成 / e2e） | 自动 | 紧 |
| 行为（runtime 探针） | 半自动（脚本 + 人工） | 中 |
| 跨组件一致性 | 人工 + 半自动 | 中（慢） |
| 品味 / 战略判断 | 人工 | 必走 |

明确每层**用什么工具 / 谁来做**。

#### D. replan budget

- 单个失败最多重试 N 次（N 推荐 1-2）
- 整层 N 个步骤都失败 → 立即 re-plan，不继续
- 用户拍"再调" → 立即停下，不是默默推进

### Step 3: 写到 todo + 告知用户

把契约**写进 `todo` 工具的 notes**，并**显式**告诉用户：

"按 task-contract，本任务的 false-success 是 X / Y / Z。继续 / 调整？"

让用户在主会话早期**有机会反对**。

### Step 4: 任务结束时核对契约

任务收尾前，**逐条**核对：

- false-success 的每一条都**被独立检查过**（不是声明"我检查了"）
- evidence 清单**全部拿到**
- verification ladder 的每一层都执行

如果某条没满足，**任务没完** —— 即使 agent 自己认为做完了。

## 与其它 skill 的接口

- **`worker-handoff`**：worker 收到的 context 应该已经包含契约。worker 的 handoff 模板里"Verification"字段对应契约 C 段。
- **`code-reviewer`**：审查时按契约 B 段（evidence）核对，不是按 worker 自述核对。
- **`adversarial-review-trigger`**：完工后必跑一次 adversarial 复核，攻击契约 A 段（false-success）的每一条。
- **`correction-funnel`**：任务结束后，false-success 真命中了 → 走 correction funnel 入 KB / memory。

## 自包含性（skill-authoring §1）

- 模板在 `templates/contract.md`，**不引用外部路径**
- 范例在 `references/example-graph-engineering-translation.md`，**不依赖其它 skill 的 SKILL.md**
- 备份 = 可用：`tar ~/.local/share/hermes/skills/hermes-agent-ops/task-contract/` 完整还原

## 何时**不**写契约

- 单文件小改（README / typo / 单个 lint 修复）
- 用户已经显式给出 success criteria
- 查询 / 闲聊 / 学习类

写契约是**默认行为**而不是**额外负担**——但过度写契约也是一种"装忙"。

## Out of scope

- 任务**完成后**的核对 → `correction-funnel`
- 任务**进行中**的 adversarial review → `adversarial-review-trigger`
- 任务**派发**给 worker 时的合约 → `worker-handoff`
- 任务**不可逆动作**的授权 → `authority-gate`

## References

- `references/example-graph-engineering-translation.md` — 本次「图论→技能化」任务的真实契约样本（端到端验证用）