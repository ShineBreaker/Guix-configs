---
name: agenote-curator
description: agenote 自动策展指南。当需要维护 agenote 记事本健康度、去重、归档陈旧条目、重新分配检索权重时使用。涵盖 agenote MCP tool 策展流程与权重机制。
---

# agenote-curator — 自动策展

定期对 agenote 记事本执行策展，保持健康度并优化检索权重。

> agenote 已改造为 MCP server，以下 `agenote_*` 均为 MCP tool 名。

## 何时策展

- 周期性维护（如每周/每次长会话后）
- 条目数明显增多（>50 条）
- 检索结果质量下降（噪音多、相关性差）
- 用户主动要求 `/agenote-curate`

## 一键策展

```
agenote_curate()
```

执行 5 个步骤：

1. **健康检查**：孤立率、过时率、类型偏斜、薄弱类别
2. **权重重分配**：根据 USAGE_COUNT 和新鲜度重新计算每张卡片的 WEIGHT
3. **去重检测**：标题相似度 + category/tech 匹配
4. **归档陈旧**：超阈值（90 天）未验证的 stale 卡片自动归档
5. **重建索引**：全量扫描 experiences/ 刷新 index.json

## 权重机制（spec §7）

检索时 agenote_search 跨域扫描人类（weight 默认 1.5）+ agent（weight 默认 1.0）卡片，最终分数 = 原始相关度 × WEIGHT。

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

## 手动维护命令（MCP tool）

```
agenote_health()                          # 查看健康度（含 by_source 跨 agent 分布）
agenote_deduplicate()                     # 只检测重复
agenote_archive(stale=true)               # 只归档陈旧
agenote_archive(list_cards=true)          # 列出已归档
agenote_restore(target="<ID>")            # 恢复归档卡片
agenote_reindex()                         # 只重建索引
agenote_memory_search(stale=true)         # 陈旧记忆
```

## 跨 agent 工作流（MCP tool，手动触发，默认 dry_run）

这三个 tool 实现"跨 agent 经验共享"，参考 MiMoCode Memory/Dream/Distill 体系，
**纯只读/启发式，不调 LLM，不写回源**，默认 dry_run 安全试跑：

```
agenote_reconcile(source="hermes")        # 只读拉取 hermes memory 进检索范围
agenote_reconcile(source="all", dry_run=True)  # 全源 dry_run 预览
agenote_dream(dry_run=True)               # 从 reconcile 事实启发式提炼候选新卡片
agenote_distill(dry_run=True)             # 把重复工作流聚成 skill 草稿（写到 .distill/）
```

- **reconcile**：把 hermes `memory_store.db` 的 facts 只读索引到 `.reconcile/index.json`，
  让 `agenote_search` 能搜到（domain=`reconcile`、source=`hermes`），weight 低于 KB 卡片。
  **三重只读保护**（mode=ro + query_only + 不构造写语句），hermes DB 绝不被改。
- **dream**：找 reconcile 事实里高频出现、KB 未覆盖的主题 → 候选新卡片。**零候选即成功**。
- **distill**：把 KB 里 `type=ascended`/`usage_count≥2` 的卡片按 category+tech 聚类 →
  SKILL.md 草稿（写 `.distill/`，**不进 skills/**，人工 move 才生效）。**零候选即成功**。

## 健康度指标解读

| 指标     | 阈值              | 含义                          |
| -------- | ----------------- | ----------------------------- |
| 孤立率   | <15% ✅ / <25% ⚠️ | 无 `[[file:]]` 链接的卡片占比 |
| 过时率   | <10% ✅ / <20% ⚠️ | stale 状态卡片占比            |
| 类型偏斜 | <45% ✅           | 单一 type 占比过高            |
| 薄弱类别 | ≥3 ✅             | 每个类别至少 3 张卡片         |
| by_source | 各 agent 分布    | `by_source.counts`：每 agent 写卡数；`unknown` 列表暴露未登记 agent |
