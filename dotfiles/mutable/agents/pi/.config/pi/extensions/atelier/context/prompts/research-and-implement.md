<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: research-and-implement
mode: chain
param: task
description: 调研-实施链：researcher → planner → worker → reviewer，需要外部文档支撑时使用
---

```json
{
  "chain": [
    { "agent": "researcher", "task": "调研以下技术需求的文档、API、兼容性：{task}" },
    { "agent": "planner", "task": "基于调研结果制定实施计划：{previous}" },
    { "agent": "worker", "task": "按计划执行实施：{previous}" },
    { "agent": "reviewer", "task": "审查实施结果：{previous}" }
  ]
}
```
