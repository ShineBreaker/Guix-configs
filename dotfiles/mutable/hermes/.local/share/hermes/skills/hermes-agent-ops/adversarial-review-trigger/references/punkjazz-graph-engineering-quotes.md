# 引用：punkjazz.ai §04 + Perez 关于 adversarial review 的原文

## punkjazz.ai §04 "When green turns red"

> The most useful test arrived after the new laptop system appeared complete. The automated suite was green, the integration tests were green, and a separate model had reviewed the artifact against the written requirements without raising an objection.
>
> I had recently seen a simple suggestion in a tweet: when an agent says the work is finished, give the result to a fresh reviewer whose job is to disprove that claim. I added that pass before using the system on the laptop. The reviewer found four problems that the existing checks had missed, including an approval boundary that could not prove human presence, a missing work record that could be mistaken for successful completion, an update that could leave mixed versions after an interruption, and a migration that could remove unrelated configuration.
>
> The completion claim was withdrawn and the task returned to execution. Each finding became an adversarial regression test before the fix was accepted. Once the changes passed the full suite, the result went back to the same reviewer, who reran the original attacks and changed the verdict from fail to pass.
>
> That sequence matters because verification can become another source of reassurance when every reviewer receives the same framing and checks the same happy path. An adversarial reviewer changes the question from whether the work satisfies its own report to whether the report can survive an attempt to break it.

提炼的攻击向量：

- **A1 (报告无 artifact)**：claim 是 "完成"，但 artifact 真在磁盘上吗？
- **A3 (activity record 缺失)**："missing work record that could be mistaken for successful completion" —— 直接对应这个 attack。
- **A8 (不可逆副作用)**："an update that could leave mixed versions after an interruption, and a migration that could remove unrelated configuration" —— git diff --stat 比预期大、git status 有未声明文件。
- **A6 (用同 framing 的 reviewer)**："every reviewer receives the same framing and checks the same happy path" —— 直接对应。

## Carlos E. Perez "Loop Engineering and The Missing Compiler"

> Reaching for a second agent as a reviewer is the natural move when you need an independent judge, and it is also the easiest place to manufacture a counterfeit one — a checker that emits crisp pass/fail verdicts but lives in the same kind of head as the worker, so the two can agree, confidently and silently, on the same blind spot. A verdict from something that shares your assumptions is theater dressed as verification.

提炼的攻击向量：

- **A10 (受信任的循环回路)**：adversarial reviewer 与 worker 共享 model / 共享 framing / 共享 evidence 链 → theater dressed as verification。

## 我们推导出但原文未明确列的攻击向量

- **A2 / A4 / A5 / A7 / A9**：从 `task-contract` skill 的 false-success conditions 表直接搬运。这是**任务开始前**写 false-success conditions 的价值：完工时直接转成 attack vector 清单。

## 复盘四问题的真实教训

punkjazz 的 reviewer 找到的 4 个问题，每个都对应一类**容易伪造的 verifier**：

| 问题 | 哪类 verifier 漏了 |
|------|--------------------|
| approval boundary that could not prove human presence | **authority 链断了** —— verifier 没核实"外部人真的批了" |
| missing work record mistaken for successful completion | **activity record 没保留** —— verifier 接受 "git status 干净" = "成功" |
| update could leave mixed versions after interruption | **原子性边界没核** —— verifier 只看 happy path 不看 partial failure |
| migration could remove unrelated configuration | **scope creep** —— verifier 没核 `git diff --stat` 与 claim 的范围是否一致 |

这 4 类在我们 hermes 栈里都有对应：
- authority 链 → `authority-gate` skill
- activity record → `correction-funnel`（但更早的版本叫 task-activity-record）
- 原子性 → `task-contract` 的 false-success 模板里要列
- scope creep → adversarial review A8 attack vector