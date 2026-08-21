---
description: 执行 agenote 策展（健康 + 去重 + 归档 + 权重重分配）
---

执行 agenote 策展流程：

1. 运行 `AGENOTE_AGENT=zcode agenote curate`（重操作，耐心等待完成）。
2. 向用户汇报策展结果：健康度变化、去重/归档了哪些卡片、权重调整情况。
3. 用 `AGENOTE_AGENT=zcode agenote commit -m "策展: <一句话总结>"` 提交知识库变更（遵守 commit 规范，含 Assisted-by trailer）。

如需先了解现状再决定，可先运行 `AGENOTE_AGENT=zcode agenote health` 查看。

$ARGUMENTS
