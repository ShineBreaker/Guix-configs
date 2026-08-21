---
description: 触发 agenote 经验总结 + 资料留痕（对应 pi /agenote-summarize）
---

请按 `agenote-review` skill 的流程，对本次会话做经验总结与留痕：

1. 评估本次对话是否有可记录的经验信号（bug/踩坑/更优方案/用户纠正/项目决策）。
2. 如有 → 通过 agenote CLI 写入（注意所有调用加 `AGENOTE_AGENT=zcode` 前缀）：
   - 一般经验：`AGENOTE_AGENT=zcode agenote add --title "标题" --entry note|mistake|ascended --stdin`
   - 跨会话偏好/项目约束：`AGENOTE_AGENT=zcode agenote memory --add --type feedback|project --stdin`
3. 本轮用到的资料留痕：已有卡片 `AGENOTE_AGENT=zcode agenote touch <ID>`；联网查到的新知识 `agenote add --type note` 写卡留档。
4. 如无可记录经验，明确回复"本次无可记录经验"。

$ARGUMENTS
