# Implement Workflow

完整实施链：context-builder → planner → worker → reviewer。

```json
{
  "chain": [
    { "agent": "context-builder", "task": "{task}" },
    { "agent": "planner", "task": "基于以下上下文制定实施计划：{previous}" },
    { "agent": "worker", "task": "按计划执行实施：{previous}" },
    { "agent": "reviewer", "task": "审查以下实施结果：{previous}" }
  ]
}
```
