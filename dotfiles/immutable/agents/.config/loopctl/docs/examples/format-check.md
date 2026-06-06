<!-- SPDX-FileCopyrightText: 2026 BrokenShine -->
<!-- SPDX-License-Identifier: MIT -->

# Example: format-check loop

## 用途

批量检查并自动修复代码格式问题。适用于 prettier、eslint、black 等格式化工具的批量修复场景。

## 启动

```bash
loopctl format-check start \
  --task "检查 src/ 目录下所有 .ts 文件的格式问题，用 prettier 自动修复" \
  --adapter pi \
  --max-iterations 20
```

也可将任务描述写入文件：

```bash
loopctl format-check start \
  --task-file .agents/workfile/loops/examples/format-check-task.md \
  --adapter pi \
  --max-iterations 20
```

## 手动推进

```bash
loopctl format-check step    # 跑一轮
loopctl format-check status  # 查看状态
loopctl format-check watch   # 实时查看输出
```

## 任务描述模板

以下内容可保存为 `format-check-task.md` 并通过 `--task-file` 引用：

```markdown
# 代码格式检查与修复

## 目标

检查 src/ 目录下所有 .ts 文件的格式问题，用 prettier 自动修复。

## 操作规范

1. 用 `prettier --check 'src/**/*.ts'` 发现所有格式问题
2. 按文件分批修复：`prettier --write <file>`
3. 每批修复后运行 `tsc --noEmit` 确认未引入类型错误
4. 修复完成后再次 `prettier --check` 验证

## 完成条件

- `prettier --check 'src/**/*.ts'` 零错误
- `tsc --noEmit` 通过
- git diff 中无功能性改动（纯格式修复）

## 约束

- 每轮修复不超过 30 个文件
- 修复后必须验证类型检查通过
- 不修改非 src/ 目录的文件
- 不做任何代码逻辑改动
```

## 检查点结构示例

```markdown
# Checkpoint: format-check iter-005

## ✅ 已完成

- 累计修复 87/120 个文件
- 本轮修复：src/api/\*.ts（23 个文件）
- `tsc --noEmit` 通过

## ⚠️ 遇到的问题

- `src/legacy/parser.ts` prettier 格式化后 tsc 报错，已回退
  → 需手动处理（文件含模板字符串拼接，格式化改变语义）

## 🎯 下一步 TODO

1. 修复 src/services/\*.ts（约 15 个文件）
2. 修复 src/utils/\*.ts（约 18 个文件）
3. 手动处理 src/legacy/parser.ts
4. 最终 `prettier --check` 全量验证

## 📂 关键文件

- `src/legacy/parser.ts` — 需手动处理
- 已修复文件列表见 git diff
```
