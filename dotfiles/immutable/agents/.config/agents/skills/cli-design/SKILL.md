---
name: cli-design
description: Use when designing a new CLI, reviewing an existing CLI for agent-friendliness, or when encountering "设计 CLI", "agent 友好的命令行", "命令行接口", "CLI 审查".
---

# CLI 设计原则

面向人类的 CLI 常阻塞 agent（交互式提示、大量前置文档、无示例的帮助文本）。Agent 优先模式应是 headless 的。

## 核心原则

### 1. 非交互优先

所有必需参数必须通过命令行 flags、环境变量或 stdin 传入。

| 坏                                                       | 好                           |
| -------------------------------------------------------- | ---------------------------- |
| `mycli deploy` → `? Which environment? (use arrow keys)` | `mycli deploy --env staging` |

### 2. 增量发现

`--help` 按 subcommand 展示，不要每次运行打印全部手册。

```bash
mycli --help          # 仅顶层命令列表
mycli deploy --help   # deploy 子命令的 flags 和示例
```

### 3. `--help` 必须含示例

不仅列举 flags，还要包含真实调用示例。

```
Usage: mycli deploy [options]

Examples:
  mycli deploy --env staging --app api
  mycli deploy --env prod --dry-run
```

### 4. 支持 stdin/管道

```bash
cat config.json | mycli config import --stdin
mycli logs --tail | grep ERROR
```

### 5. 快速失败

缺少必需参数时立即报错，并给出正确示例调用。不要挂起等输入。

```
Error: --env is required

Example: mycli deploy --env staging
```

### 6. 幂等性

重复运行安全：

- 已存在 → "already exists"
- 无变化 → 安全 no-op
- 避免副作用累积

### 7. 破坏性操作需防护

- `--dry-run` 预览变更
- `--yes` / `--force` 显式确认
- 默认行为保守，不自动覆盖/删除

### 8. 一致结构

统一 `resource verb` 模式：

```bash
mycli app list
mycli app create --name api
mycli app delete --name api
mycli config get key
mycli config set key value
```

### 9. 结构化成功输出

成功时返回机器可用的数据，不仅是装饰性文本：

```json
{
  "id": "deploy-123",
  "url": "https://...",
  "duration_ms": 4500,
  "status": "success"
}
```

## 审查检查清单

审查现有 CLI 时逐一检查：

- [ ] 是否存在交互式提示？
- [ ] `--help` 是否包含示例？
- [ ] 是否支持 stdin 管道输入？
- [ ] 缺少参数时是否快速失败并给出示例？
- [ ] 关键操作是否幂等？
- [ ] 破坏性操作是否有 `--dry-run`？
- [ ] 命令结构是否一致（resource verb）？
- [ ] 成功输出是否包含机器可用数据？
- [ ] 错误输出是否包含正确调用示例？

## 反模式速查

| 反模式                   | 修复                             |
| ------------------------ | -------------------------------- |
| 交互式选择环境           | `--env` flag                     |
| 运行后打印整本手册       | 仅打印相关 subcommand 帮助       |
| `--help` 只有 flags 列表 | 添加 2-3 个真实示例              |
| 不支持管道               | 添加 `--stdin` 或读取 stdin      |
| 挂起等用户输入           | 缺少参数时立即报错 + 示例        |
| 重复运行产生重复资源     | 检查已存在，返回 idempotent 结果 |
| `rm -rf` 式默认行为      | `--dry-run` + `--force`          |
| 命令命名随意             | 统一 `resource verb` 模式        |
| 只有"操作成功"文本       | 返回 JSON/结构化数据             |
