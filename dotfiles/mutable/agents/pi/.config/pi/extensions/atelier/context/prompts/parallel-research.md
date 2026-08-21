<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: parallel-research
mode: parallel
param: topic
description: 多方向并行调研，结果汇总后制定综合方案
---

```json
{
  "tasks": [
    { "agent": "researcher", "task": "调研方向A：{topic}" },
    { "agent": "researcher", "task": "调研方向B：{topic}" },
    { "agent": "scout", "task": "定位当前项目中与 {topic} 相关的所有代码和配置" }
  ]
}
```
