# Task Contract — <任务简述>

> 来源：punkjazz.ai §03 "What a task carries" + Carlos E. Perez "Loop Engineering" ladder。
> 用途：让任务**开始前**写清楚"什么算看起来成功但其实没做好"，让 verifier 后续有依据证伪完工声明。

## 1. False-Success Conditions（必填，至少 3 条）

什么情况下，这个任务会"看起来成功但其实没做好"？

- [ ] **F1**: <例："任务说做完了，但磁盘上没有 working artifact">
- [ ] **F2**: <例："测试套件绿，但 success criteria 被偷偷改了">
- [ ] **F3**: <例："git status 干净，但 commit log 看不到做过的痕迹">

（按需加 F4...Fn，每条都要"如果发生就判失败"的明确语义）

## 2. Expected Evidence（必填）

任务完成时**必须能拿出来**的 evidence：

- **改了哪些文件**（路径清单）
- **跑了哪些验证**（命令 + 结果）
- **留了哪些日志 / artifact 路径**
- **谁 / 什么做了独立复核**

## 3. Verification Approach（按 Perez ladder 分层）

| 层 | 用什么 | 紧度 | 谁来做 |
|----|--------|------|--------|
| 静态（formatter / linter / type） | | 紧 | 自动 |
| 行为（unit / e2e） | | 紧 | 自动 |
| 行为（runtime 探针） | | 中 | 半自动 |
| 跨组件一致性 | | 中（慢） | 人工 + 脚本 |
| 品味 / 战略 | | 必走 | 人工 |

每层必须**明确**用什么工具 / 谁来做。

## 4. Replan Budget（必填）

- 单个失败最多重试 N 次：___
- 整层 N 个步骤都失败 → 立即 re-plan，不继续
- 用户拍"再调" → 立即停下重新对齐

## 5. Counter-Metric（Perez Paired Metrics，可选但推荐）

每个 success metric 配一个 counter-metric（捕捉"作弊路径"）：

- success: ___  → counter: ___
- success: ___  → counter: ___

**paired metric 的本质**（Carlos E. Perez《From Loop to Graph》）：
- success metric 升高是 agent 想要的
- counter metric 升高是 **作弊路径在生效**（Goodhart）
- 配对之后，单独看 success 绿 = 不够；必须**两者都正常**才算完成

**典型配对**：

| 场景 | success metric | counter metric |
|------|----------------|----------------|
| 客服 bot | ticket 解决率 | 客户续费率 / 投诉率 |
| 代码生成 | 测试通过率 | 代码 review 拒绝率 / bug 报告 |
| skill verify | verify PASS 数 | false-positive 漏检数 / 真实场景触发率 |
| 文件删除 | 释放空间 | 可恢复率（trash 而非 rm）/ 误删恢复 |

**反模式**：

- ❌ 只有 success 没 counter（agent 可攻破）
- ❌ counter 与 success 同源（同 metric 派生 = 回路检查 = 假独立）
- ❌ counter 是 agent 自己报告的（要外部测量）

---

## 核对清单（任务收尾前用）

- [ ] F1 - Fn 每条都**被独立检查过**（不是声明"我检查了"）
- [ ] evidence 全部拿到
- [ ] verification ladder 每层都执行
- [ ] counter-metrics（如果声明了）**都实际查过值**，不是信 worker 自报
- [ ] user 已 review 收尾（或明确授权自动收尾）