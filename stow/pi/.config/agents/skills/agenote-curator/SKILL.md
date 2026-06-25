---
name: agenote-curator
description: agenote 自动策展指南。当需要维护 agenote 记事本健康度、去重、归档陈旧条目、重新分配检索权重时使用。涵盖 kb agenote curate 流程与权重机制。
---

# agenote-curator — 自动策展

定期对 agenote 记事本执行策展，保持健康度并优化检索权重。

## 何时策展

- 周期性维护（如每周/每次长会话后）
- 条目数明显增多（>50 条）
- 检索结果质量下降（噪音多、相关性差）
- 用户主动要求 `/agenote-curate`

## 一键策展

```bash
kb agenote curate
```

执行 5 个步骤：

1. **健康检查**：孤立率、过时率、类型偏斜、薄弱类别
2. **权重重分配**：根据 USAGE_COUNT 和新鲜度重新计算每张卡片的 WEIGHT
3. **去重检测**：标题相似度 + category/tech 匹配
4. **归档陈旧**：超阈值（90 天）未验证的 stale 卡片自动归档
5. **重建索引**：全量扫描 experiences/ 刷新 index.json

## 权重机制（spec §7）

检索时 agenote search 跨域扫描人类（weight 默认 1.5）+ agent（weight 默认 1.0）卡片，最终分数 = 原始相关度 × WEIGHT。

**curate 时的权重重分配公式**：

```
新 WEIGHT = 基础权重 × 使用系数 × 新鲜度系数

基础权重:   人类=1.5, agent=1.0
使用系数:   1 + 0.1 × min(USAGE_COUNT, 10)   # 常用的提升，上限 +1.0
新鲜度系数: last_used 超 STALE_DAYS(30天) → 0.8，否则 1.0
```

效果：

- 频繁使用的卡片权重爬升（最高 1.0 → 2.0）
- 长期不用的卡片权重衰减（×0.8）
- 人类卡片整体权重高于 agent 卡片

## 手动维护命令

```bash
kb agenote health              # 查看健康度
kb agenote deduplicate         # 只检测重复
kb agenote archive --stale     # 只归档陈旧
kb agenote archive --list      # 列出已归档
kb agenote restore <ID>        # 恢复归档卡片
kb agenote reindex             # 只重建索引
kb agenote memory --stale      # 陈旧记忆
kb agenote memory --stale --auto-archive-days 60  # 自动归档陈旧 feedback
```

## 健康度指标解读

| 指标     | 阈值              | 含义                          |
| -------- | ----------------- | ----------------------------- |
| 孤立率   | <15% ✅ / <25% ⚠️ | 无 `[[file:]]` 链接的卡片占比 |
| 过时率   | <10% ✅ / <20% ⚠️ | stale 状态卡片占比            |
| 类型偏斜 | <45% ✅           | 单一 type 占比过高            |
| 薄弱类别 | ≥3 ✅             | 每个类别至少 3 张卡片         |
