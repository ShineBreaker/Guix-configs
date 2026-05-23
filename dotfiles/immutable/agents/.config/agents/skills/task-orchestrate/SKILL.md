---
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

name: task-orchestrate
description: Use when decomposing complex tasks into subagent trees, managing parallel workers, or when encountering multi-file/multi-domain work that requires Planner/Worker/Verifier coordination.
---

# 任务编排

将复杂任务分解为并行子任务树，通过结构化 handoff 协议协调 Planner、Worker、Verifier 三级节点。

> 本 skill 与 Pi subagent 体系映射：Planner = 主 agent，Worker = subagent（scout/worker/researcher 等），Verifier = reviewer。

## 触发条件

- 任务涉及代码库探索 + 架构判断 + 实现 + 审查中任意两项以上
- 需要修改多个不相关文件或跨多个领域
- 用户明确要求"并行处理"或"分解任务"

## 节点类型

| 节点     | 运行循环 | 职责                             | 输出            |
| -------- | -------- | -------------------------------- | --------------- |
| Planner  | 是       | 规划整体目标、监控进度、决定停止 | 计划 + 最终交付 |
| Worker   | 否       | 执行单一具体任务                 | 结构化 handoff  |
| Verifier | 否       | 验收关键任务的输出               | 裁决 handoff    |

## 核心原则

1. **Planner 只规划不编码** — 分配任务、读取 handoffs、决定下一步，不直接编辑文件
2. **Worker 相互隔离** — 每个 worker 拥有独立上下文，不共享中间状态，不横向通信
3. **通过 handoff 持续运动** — 无"完成"状态直到 Planner 决定停止；新 handoff 到达必须处理
4. **传播而非同步** — 上游 handoff 通过 `dependsOn` 机制 relay 到下游，不共享内存状态

## 分解流程

1. **Discovery** — 先用 scout/researcher 收集上下文，理解代码库/文档现状
2. **切片** — 按文件边界、领域边界或逻辑依赖将任务切分为独立单元
3. **分配** — 每个切片分配一个 Worker，明确输入、输出、验收标准
4. **驱动** — 并行启动无依赖的 Worker，有依赖的等待上游 handoff
5. **验收** — 关键 Worker 输出后启动 Verifier 验证
6. **汇总** — Subplanner（如有递归）汇总子 handoff 向上汇报

## Handoff 协议

Worker 完成任务后输出：

```markdown
<!-- handoff: task=<任务名>, status=success|blocked|partial|error -->

## 状态

success / blocked / partial / error

## 分支/上下文

- 相关文件/分支
- 运行环境信息

## 执行摘要

- 做了什么
- 关键发现
- 测量数据（命令 + 数值，用于漂移检测）

## 偏差与注意事项

- 与预期的偏差
- 风险点
- 需要父节点关注的发现

## 建议后续

- 下游任务建议
- 需要其他 Worker 配合的事项
```

### 失败分类与重试

| 失败模式     | 识别特征                               | 重试策略               |
| ------------ | -------------------------------------- | ---------------------- |
| cap-hit      | 运行时长接近上限 + terminal error      | 缩小范围重试           |
| oom          | 输出含 `out of memory` / exit code 137 | 缩小范围重试           |
| network-drop | `fetch failed` / `ETIMEDOUT`           | 直接重试（瞬态）       |
| tool-error   | 工具调用失败                           | 换方式重试             |
| unknown      | 其他                                   | 重试一次，再失败则上报 |

同一任务最多重试 2 次。

## Verifier 验收格式

```markdown
## 验收结果: pass | blocked | fail

## 目标

- 验收的任务名

## 执行验证

- 实际运行的测试/检查命令

## 发现

- 逐条验收标准的结论

## 建议

- 修复建议或后续行动
```

## 与 Pi 的映射

| 编排概念 | Pi 实现                                    |
| -------- | ------------------------------------------ |
| Planner  | 主 agent（你）                             |
| Worker   | `subagent` 工具（scout/worker/researcher） |
| Verifier | `subagent` + reviewer agent                |
| Handoff  | subagent 返回的 task 结果文本              |
| Plan     | 你的内部计划（可用 todo 工具追踪）         |
| State    | `todo` 工具的 task 状态                    |
| Git 共享 | 所有 Worker 操作同一工作树                 |

## 防护

- 不扩展用户目标，不加规划启发式
- 保持 fan-in 小，最小化路径重叠
- Merges 也是任务，默认加 Verifier
- 使用量化声明（`measurements[]`）便于后续漂移检测
