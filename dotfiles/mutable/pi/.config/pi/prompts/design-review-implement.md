<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

# Design Review Implement

完整实施链（含架构审查）：scout (thorough) → planner → oracle → worker → reviewer。

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

## 使用场景

- 涉及架构变更的重大功能
- 需要第二意见确认方向正确
- 技术选型不确定时

## 与普通 implement 链的区别

| 环节     | implement      | design-review-implement    |
| -------- | -------------- | -------------------------- |
| 侦察     | scout (medium) | scout (thorough)           |
| 计划     | planner        | planner                    |
| **审查** | —              | **oracle（架构第二意见）** |
| 实施     | worker         | worker                     |
| 代码审查 | reviewer       | reviewer                   |
