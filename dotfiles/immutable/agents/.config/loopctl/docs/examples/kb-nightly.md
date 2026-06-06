<!-- SPDX-FileCopyrightText: 2026 BrokenShine -->
<!-- SPDX-License-Identifier: MIT -->

# Example: kb-nightly loop

## 用途

每夜扫描知识库，整理过期卡片（>30 天未验证），修复/归档/删除，验证链接有效性。

## 启动

```bash
loopctl kb-nightly start \
  --task "扫描知识库，整理过期卡片（>30天未验证），修复/归档/删除" \
  --adapter pi \
  --max-iterations 10
```

也可将任务描述写入文件：

```bash
loopctl kb-nightly start \
  --task-file .agents/workfile/loops/examples/kb-nightly-task.md \
  --adapter pi \
  --max-iterations 10
```

## 手动推进

```bash
loopctl kb-nightly step    # 跑一轮
loopctl kb-nightly status  # 查看状态
loopctl kb-nightly watch   # 实时查看输出
```

## 任务描述模板

以下内容可保存为 `kb-nightly-task.md` 并通过 `--task-file` 引用：

```markdown
# 知识库夜间策展

## 目标

扫描知识库中超过 30 天未验证的卡片，逐一检查：

1. 内容是否仍然准确（检查代码引用、链接有效性）
2. 是否已被其他卡片覆盖（重复检测）
3. 是否应该归档或删除

## 操作规范

- 使用 `kb list --all` 获取完整卡片列表
- 使用 `kb health` 检查知识库整体健康度
- 过期卡片：先 `kb review <id>`，再决定 `kb touch`（确认有效）、`kb archive`（归档）或删除
- 链接失效的卡片：修复链接后 `kb touch`
- 发现重复：`kb merge <primary> <secondary>`

## 完成条件

- 所有 >30 天未验证的卡片已处理（touch / archive / merge / 删除）
- `kb health` 无红色警告
- 输出摘要：处理了多少卡片、归档了多少、修复了多少链接

## 约束

- 不要删除任何卡片，只做归档（保守策略）
- 每轮处理不超过 20 张卡片，避免单轮过长
```

## 检查点结构示例

以下是典型 checkpoint 内容，agent 每轮结束后写入：

```markdown
# Checkpoint: kb-nightly iter-003

## ✅ 已完成

- `kb health` 检查：1 个警告（3 张卡片 >60 天 stale）
- 处理了 15 张过期卡片：
  - 8 张 `kb touch`（内容验证有效）
  - 5 张 `kb archive`（内容过时）
  - 2 张 `kb merge`（重复主题）

## ⚠️ 遇到的问题

- 卡片 20260401-xxx 的外部链接 404，已标记待修复
- `kb deduplicate` 发现 2 对疑似重复，需人工确认

## 🎯 下一步 TODO

1. 修复卡片 20260401-xxx 的失效链接
2. 处理剩余 5 张 >30 天卡片
3. 最终 `kb health` 验证

## 📂 关键文件

- `.agents/kb/` — 知识库目录
```
