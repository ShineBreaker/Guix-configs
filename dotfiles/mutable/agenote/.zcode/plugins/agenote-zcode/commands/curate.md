---
description: 执行 agenote 策展（健康 + 去重 + 归档 + 权重重分配）
---

按 `agenote-curator` skill 执行策展：读取 `~/.config/agents/skills/agenote-curator/SKILL.md`，严格遵循其「策展流程（agent 主导）」Step 0–10；具体步骤与子步（3.5 / 4.5 / 7.5 / 8.5 / 8.6 等）一律以 skill 原文为准，不在本文件复制。流程编排与去留决策由 agent 执行。

注意：

- 所有 CLI 调用带 `AGENOTE_AGENT=zcode` 前缀（否则卡片归因错误落到 pi）。
- 触发 skill 的 Andon 机制（严重矛盾 / 单次策展新增卡片 >10 张 / 已有 pattern 被推翻 / 用户画像冲突）时暂停自动流程，输出问题描述、涉及 ID 与三种处理建议，等待人工决策。
- 收尾不可省略（Step 9）：`reindex` → `lint --fix` → `git status --short` 核对改动 → `agenote commit -m "策展: <50 字内总结>" --dry-run` 预览后真提交（commit 含 Co-authored-by trailer）。遗留改动与本轮产物分两个 commit。
- 最后按 skill「报告格式」向用户输出策展报告。

$ARGUMENTS
