---
name: git-summary
description: Use when generating work summaries, weekly reports, status updates from git history, or when encountering "这周做了什么", "总结最近提交", "生成周报", "what did I get done".
---

# Git 工作摘要

从 git commit 历史生成简洁的工作摘要，用于状态更新、周报或回顾。

## 触发条件

- 用户要求总结一段时间的工作
- 用户要求生成周报/日报
- 需要基于实际交付编写状态更新

## 收集流程

1. **确定作者** — 读取当前 git 用户 email（`git config user.email`）
   - 缺失时要求用户先设置

2. **确定时间范围** — 解析用户请求为具体日期
   - "这周" → 过去 7 天
   - "最近" → 过去 7-10 天
   - 明确日期 → 按用户指定

3. **收集提交** — 在主要分支上筛选作者提交

   ```bash
   git log --author="<email>" --since="<date>" --oneline --no-merges
   ```

4. **排除噪音** — 排除：
   - merge commits
   - 纯格式化、导入重排、小重命名
   - 未暂存的本地更改

5. **分组综合** — 将剩余提交按主题归纳为 2-5 个 bullet

## 分类体系

将变化归类为：

- **bug fix** — 修复行为、解决回归
- **tech debt** — 重构、简化、清理、依赖升级
- **net-new** — 新功能、新模块、新工具
- **docs/config** — 文档更新、配置变更（可选单独列出）

## 输出格式

```markdown
## 工作摘要（YYYY-MM-DD 至 YYYY-MM-DD）

### 主要交付

- [bullet 1：做了什么 + 影响]
- [bullet 2]
- ...

### 分类

- Bug fix: N 处
- Tech debt: N 项
- Net-new: N 项

### 备注

- [如时间范围有调整，说明实际使用的范围]
```

## 防护

- 极度简洁，信息密度高
- 优先有意义的行为或架构变化
- 不推断意图或动机，功能性地描述变更
- 仅基于 commit 历史和 diff，不编造未发生的工作
