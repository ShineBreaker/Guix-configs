<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: implement
mode: chain
param: task
description: 完整实施链：scout(thorough) → planner → worker → reviewer
---

```json
{
  "chain": [
    { "agent": "scout", "task": "深度侦察（thorough）：{task}" },
    { "agent": "planner", "task": "基于以下上下文制定实施计划：{previous}" },
    { "agent": "worker", "task": "按计划执行实施：{previous}" },
    { "agent": "reviewer", "task": "审查以下实施结果：{previous}" }
  ]
}
```
