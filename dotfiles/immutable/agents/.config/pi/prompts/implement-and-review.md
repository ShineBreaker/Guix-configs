# Implement and Review

实施与修复链：worker → reviewer → worker (fix)。

```json
{
  "chain": [
    { "agent": "worker", "task": "{task}" },
    { "agent": "reviewer", "task": "审查实施结果：{previous}" },
    { "agent": "worker", "task": "根据审查反馈修复：{previous}" }
  ]
}
```
