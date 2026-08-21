---
name: adversarial-review-trigger
description: '在 worker 或主会话报"任务完成"后，强制触发一次**对抗性审查**——不是验证 happy path 而是**试图推翻**完工声明。来源 punkjazz.ai §04 "When green turns red" + Perez "Independence is the part that is easy to fake"。触发词：''完工后审查 / 对抗审查 / red team / 推完工声明 / 怀疑完成 / task 完成后 / 给我做个 red team / adversarial''，或在 task-contract 任务的 verify 阶段。'
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags:
      [
        adversarial-review,
        red-team,
        completion-claim,
        verification,
        independence,
      ]
    related_skills:
      [task-contract, code-reviewer, worker-handoff, correction-funnel]
---

# adversarial-review-trigger — 完工后的对抗性审查

## 核心命题

**`code-reviewer` 是验证 happy path。adversarial-review 是攻击 happy path。**

来源方法论：

- punkjazz.ai §04 "When green turns red" —— reviewer 的工作不是验证完成，而是**试图推翻**完成声明。
- Perez "Loop Engineering" —— **独立性是最容易伪造的 verifier 属性**。两个 model 用同样 framing 检查同样的 happy path，会**沉默地共享同一盲点**。

## 何时使用（trigger）

满足以下**任一**条件：

- 任务有 `task-contract`，进入 verify 阶段
- worker 报 `Status: success`，主会话准备接收 handoff
- 主会话自己宣告完成且涉及**多文件 / 跨会话 / 长期**改动
- 用户显式说"红队一下 / 怀疑完成 / 攻击这个声明"
- 用户问题里有"怕出岔子"、"再确认一下"、"再独立看一下"

不适用：

- 单文件 typo / README 修改
- 查询类任务

## 工作流程（5 步）

### Step 1: 加载完成声明

拿到 worker 的 handoff（或主会话自己的完成声明）。读这些：

- Status: success
- Branch: <branch>
- Verification: <level>
- Measurements: <metrics>
- Notes / concerns / deviations / findings

### Step 2: 加载 task-contract（如有）

如果任务有 task-contract：

- 把 false-success conditions 当**攻击向量清单**
- 每一条 F1-Fn 都必须尝试构造**反例**
- counter-metrics（如果声明）必须查实际值，不能信声明

### Step 3: 改 framing → 加载 `code-reviewer` skill 但**改 framing**

**关键变化**：`code-reviewer` 默认 framing 是"这代码质量如何"。adversarial-review 的 framing 是：

> **"任务说完成。我现在的工作是**试图推翻这个声明**。找到的每一个失败模式都是成功。"**

具体 attack vectors（最少列 3 个）：

| Attack Vector                                 | 问自己                                                                            |
| --------------------------------------------- | --------------------------------------------------------------------------------- |
| **A1: 报告无 artifact**                       | 真有 working artifact 吗？claim 是"我做了 X"，disk 上 X 真存在？                  |
| **A2: 测试绿但断言改了**                      | 测试通过 = 真完成了？测试断言有没有被偷偷放宽？边界 case 测了吗？                 |
| **A3: workspace 干净但 activity record 丢了** | git status 干净，但中间步骤有 commit / 日志 / artifact 可证明做过的痕迹吗？       |
| **A4: 只测了 happy path**                     | 失败模式 / 异常输入 / 并发 / 边界都测了吗？                                       |
| **A5: 子任务被吞**                            | N 个子任务里部分完成 / 部分 blocked 被忽略了吗？                                  |
| **A6: 用同 framing 的 reviewer**              | 复核用的是和 worker 同 model？同 toolsets？ → 同盲点风险                          |
| **A7: success metric 被攻破**                 | success metric 被 gamer 攻破了吗？counter-metric 查了吗？                         |
| **A8: 不可逆副作用**                          | 改了不该改的文件吗？（`git diff --stat` 比预期大？`git status` 有未声明的文件？） |
| **A9: 长期衰减**                              | 数据管道 / 测量方式 / 环境状态是否在过程中变了？（Goodhart's law）                |
| **A10: 受信任的循环回路**                     | 这次的"独立复核"是否真的是独立的？还是和 worker 在同一个证据链上？                |

### Step 4: 执行 attack，输出 findings

按 `code-reviewer` 的格式输出，但**focus 在 attack vector** 而不是 code quality。每个 attack vector 一节：

```markdown
## Attack Vector A<n>: <name>

**Claim being attacked**: <worker 说的什么>
**Attack**: <具体怎么构造反例 / 跑哪个命令>
**Result**: PASS（攻击失败 = 完工声明仍然成立）/ FAIL（攻击成功 = 完工声明撤回）
**Evidence**: <命令输出 / 文件路径 / commit hash>
```

### Step 5: 决策门控

| 攻击结果                           | 决策                                                                  |
| ---------------------------------- | --------------------------------------------------------------------- |
| 全部 attack FAIL（找不到推翻证据） | 任务真正完成 → 走 correction-funnel 入 KB / 关闭                      |
| ≥ 1 attack PASS（找到推翻证据）    | 任务**撤回** → 回到 worker / 主会话 → 把 finding 当**新 requirement** |
| 攻击本身方法论不够                 | 重新跑 attack vector，不直接接受攻击失败                              |

## 与其它 skill 的接口

- **前置**：`task-contract`（如果有契约，按契约 false-success conditions 攻击）
- **后置**：`correction-funnel`（找到的 finding 必走 funnel）
- **复用**：`code-reviewer` skill 的**格式**（四维审查 / severity / PASS-FAIL 门控），但**改 framing**
- **复用**：`worker-handoff` 的 handoff 模板（从哪里读完成声明）

## 独立性硬约束（防"独立 reviewer 是同 blind spot 的另一个 reviewer"）

### 当前 hermes delegate_task 的限制

调研结果（2026-07-20）：`delegate_task` **不支持** per-task `model`/`provider` 参数。子 agent 默认**共享父 model**。这意味着"自动换 model 跑独立 review"在 hermes 当前 API 下做不到。

来源：`tools/delegate_tool.py::delegate_task()` 签名只接受 `goal/context/tasks/max_iterations/role/background/parent_agent`，无 model 参数。

### Workaround（按优先级）

**W1（推荐）：换 framing + 换 toolset 路径**

最低成本的"独立性"。让子 agent 真的跑命令、读文件，而不是只读 worker 给的 evidence：

```python
delegate_task(
    goal="""你是一个 **adversarial reviewer**。
你的工作**不是**验证 worker 的完成声明，而是**试图推翻**它。
读 worker 的 handoff 找 attack vector。
必须**实际跑** attack 命令（不要只信 worker 的 claims）。
每次 attack 输出:
- Attack Vector A<n>
- Claim being attacked: <worker 说的什么>
- Attack: <跑的哪个命令>
- Result: PASS（attack 失败=完工仍成立）/ FAIL（attack 成功=完工撤回）
- Evidence: <真实命令输出>
""",
    context="""worker handoff 全文 + task-contract 全文
必须用 code-reviewer skill 的格式输出""",
    toolsets=['terminal', 'file', 'code_execution'],  # 强调可执行
)
```

关键：toolsets 里**必须有 terminal** —— 否则子 agent 只能读 evidence 不能验证。

**W2（更好但成本高）：开独立 hermes 进程**

```bash
# 在 tmux / shell 里开一个**不同 model** 的 hermes 实例
terminal(command="tmux new-session -d -s reviewer 'HERMES_MODEL=anthropic/claude-opus-4 hermes --worktree'", timeout=10)
terminal(command="sleep 8 && tmux send-keys -t reviewer '你是 adversarial reviewer...' Enter", timeout=15)
```

适用：长 review、需要真独立 model、成本不敏感。

**W3（最低成本）：主会话自审 + 强制读 evidence**

主会话**自己**跑 attack vector，但**至少自己跑命令验证 evidence**，不只读 worker claims：

- 跑 `git log --stat` 看 commit 真实改动
- 跑 `find` / `cat` 看 artifact 真实存在
- 跑 `bash -n` 看脚本真实可执行

**这个 worktree 至少要单跑 verify 脚本**（每个 skill 都有 `scripts/verify-*.py`）。

### 强制底线（无论用哪个 workaround）

- ❌ **不**接受"我看 worker handoff 觉得 OK" → 这就是同 framing + 同 blind spot
- ❌ **不**让子 agent 只用 `code_execution` 不给 `terminal` → 没法真验证
- ✅ **必须**改 framing：明确告诉子 agent "你是 attacker"
- ✅ **必须**让子 agent 跑命令（即使主会话代跑）
- 至少**换工具路径**：让子任务真的跑命令、不只是读 worker 给的 evidence

## Out of scope

- 任务**开始前**的契约 → `task-contract`
- 任务**完成后**的 KB 入库 → `correction-funnel`
- 单文件 / 小改 → 不必跑 adversarial

## References

- `references/punkjazz-graph-engineering-quotes.md` — punkjazz.ai §04 原文引用 + 我们从中提炼的 attack vectors 推导
