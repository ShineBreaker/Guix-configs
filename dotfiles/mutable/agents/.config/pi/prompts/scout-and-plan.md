<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: scout-and-plan
mode: chain
param: task
description: 侦察与规划链：scout → planner，只出计划不动手
---

```json
{
  "chain": [
    { "agent": "scout", "task": "{task}" },
    { "agent": "planner", "task": "基于侦察结果制定计划：{previous}" }
  ]
}
```
