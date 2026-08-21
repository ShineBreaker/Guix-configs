# 范例：把「图论 → 技能化」任务写成 task-contract

> 这是 2026-07-20 那个把 punkjazz.ai "Graph Engineering" + Perez "Loop Engineering" + Perez "From Loop to Graph" 三篇文章提炼成 hermes skills 的真实任务契约。**用作 task-contract skill 的端到端验证样本**。

## 1. False-Success Conditions

- [x] **F1**: 6 个 skill 全部写完，但没端到端验证一次 → false success。fixture 全过但真实场景失败。
- [x] **F2**: skill 写得"看起来合理"，但实际不挂任何 trigger → agent 加载但不触发，等于零。
- [x] **F3**: 每个 skill 都自包含正确，但互相之间是同义反复（agent 加载时 context 重复膨胀）。
- [x] **F4**: 跑通 ad-hoc verify，但 hermes runtime 加载 skill 时路径错 / frontmatter 解析错 → 文件在磁盘但 agent 看不见。
- [x] **F5**: 写完后不写 KB 卡片 → skill 进栈但用户日后搜不到为什么这么设计。
- [x] **F6**: 第三档代码部分悄悄改了用户的 hermes 配置（如 `approvals.mode` 默认值）→ 用户没拍板。

## 2. Expected Evidence

- 每个 skill 都有 SKILL.md + 至少 1 个 scripts/ 或 templates/
- 每个 skill 都跑 ad-hoc verify（fixtures + PASS/FAIL tally + cleanup）
- `hermes skills list` 能看到新 skill + 0 disabled
- 每个 skill 至少 1 张 KB 卡片解释设计选择（agenote）
- 第三档（如实现）走 `git status` 严格边界，不动用户未授权文件

## 3. Verification Approach

| 层 | 用什么 | 紧度 | 谁来做 |
|----|--------|------|--------|
| 静态（SKILL.md 语法 / frontmatter） | python ad-hoc verify 脚本 | 紧 | 自动 |
| 行为（skill 真被 hermes 加载） | `hermes skills list` 探针 | 紧 | 自动 |
| 行为（skill 触发词命中） | 人工 review：模拟用户说触发词 | 中 | 人工 |
| 行为（跨 skill 一致性） | 串接跑 task-contract → correction-funnel | 中（慢） | 脚本 + 人工 |
| 品味 / 战略 | 用户拍板 | 必走 | 人工 |

## 4. Replan Budget

- 单个 skill 写完失败 → 最多重写 1 次
- 整档（6 个 skill）端到端跑通 → 失败 ≥ 2 个 skill 就 re-plan
- 用户拍"再调" / 反馈"方向错" → 立即停下重新对齐

## 5. Counter-Metrics

- success: skill 进 `hermes skills list` → counter: skill 实际加载时 frontmatter 不报 parse error
- success: ad-hoc verify 100% PASS → counter: skill 不在真实场景触发
- success: KB 卡片写入 → counter: 卡片能被 `agenote_search` 召回且内容准确

---

## 核对结果（任务收尾用）

最终逐条核对 + 留痕。