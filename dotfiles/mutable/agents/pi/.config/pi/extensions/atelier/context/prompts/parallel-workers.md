<!--
SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>

SPDX-License-Identifier: MIT
-->

---
name: parallel-workers
mode: parallel
param: task
description: 拆分大型任务为 N 个独立子任务，让 N 个 worker 并行实施（worker 必须并发的标准模式）
---

将以下任务拆分为 N 个**互相独立、无文件冲突**的子任务，每个子任务由一个 worker 并行执行：

{task}

每个 worker 的子任务应满足：

- **单一目标**：每个 worker 只做一件事（修改一个模块 / 实现一个特性 / 修复一个 bug）
- **文件不重叠**：N 个 worker 不能修改同一个文件（避免 git 冲突）
- **自包含**：每个子任务包含完整的上下文（要改什么、验收标准、约束），worker 无需猜测

输出 N 个 `{ agent: "worker", task: "<子任务描述>" }` 条目到 `tasks` 数组。
