<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: design-review-implement
mode: chain
param: task
description: 完整实施链（含架构审查）：scout(thorough) → planner → oracle → worker → reviewer
---

```json
{
  "chain": [
    { "agent": "scout", "task": "深度侦察（thorough）：{task}" },
    { "agent": "planner", "task": "基于侦察结果制定实施计划：{previous}" },
    {
      "agent": "oracle",
      "task": "审查以下架构方案的假设、风险和替代方案：{previous}"
    },
    { "agent": "worker", "task": "按批准方案实施：{previous}" },
    { "agent": "reviewer", "task": "审查实施结果：{previous}" }
  ]
}
```
