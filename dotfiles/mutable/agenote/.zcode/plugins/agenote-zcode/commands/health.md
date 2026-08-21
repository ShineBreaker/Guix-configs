---
description: 显示并解读 agenote 健康度报告
---

1. 运行 `AGENOTE_AGENT=zcode agenote health` 获取健康度报告。
2. 向用户解读关键指标：总卡片数、孤立率、过时率、stale 卡片、各 agent 写卡分布（by_source）。
3. 如有 ⚠️/❌ 项，给出对应的处理建议（如 `agenote deduplicate`、`agenote curate`、归档 stale 卡片）。

$ARGUMENTS
