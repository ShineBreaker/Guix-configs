# Upstream issue: include fact_id in prefetch injection lines

- **状态**: 历史记录；当前 provider 和补丁均已停用（无需提交）
- **仓库**: https://github.com/NousResearch/hermes-agent
- **创建后**: 把 issue 链接回填到 plans/2026-08-29-general-assistant.md §2.1

## Title

历史记录：外部记忆的 fact_id 注入补丁（现已停用）

## Body

旧实现曾通过 `prefetch()` 钩子（实现约在 line ~161）注入如下上下文：

```
- [trust] content
```

当时的反馈工具要求 fact id，但被动召回只注入 top-5 内容，没有可反馈的句柄，因此信任训练无法覆盖被动召回，`final_score` 退化为纯相关性排序。

同一调查还发现：`retrieval_count` 只在无生产调用方的 `store.search_facts()` 中递增，而 prefetch 和历史搜索都走 `FactRetriever.search()`（`retrieval.py:48`），所以该指标不能证明实际召回。

### 当时提案

在注入行中包含 fact id：

```python
lines = [f"- [{r.get('trust_score', r.get('trust', 0)):.1f}] (#{r.get('fact_id', '?')}) {r.get('content', '')}" for r in results]
```

这是一行 diff；当时本地验证过信任漂移与被动召回反馈。当前 provider 和补丁均已停用。

### 历史补丁（当前不应用）

```diff
diff --git a/<已停用的外部记忆实现> b/<已停用的外部记忆实现>
--- a/<已停用的外部记忆实现>
+++ b/<已停用的外部记忆实现>
@@ -158,7 +158,7 @@
             return ""
         try:
             results = self._retriever.search(query, min_trust=self._min_trust, limit=5)
-            lines = [f"- [{r.get('trust_score', r.get('trust', 0)):.1f}] {r.get('content', '')}" for r in results]
+            lines = [f"- [{r.get('trust_score', r.get('trust', 0)):.1f}] (#{r.get('fact_id', '?')}) {r.get('content', '')}" for r in results]
             return "## 已停用的外部记忆\n" + "\n".join(lines) if results else ""
         except Exception as e:
             logger.debug("外部记忆 prefetch failed: %s", e)
```

## 本地维护记录

- 2026-08-29 建档（补丁基于当时的循环写法，`lines.append(...)`）。
- 2026-09-17 曾按上游列表推导式重生成补丁并更新兼容提示；现已停用，兼容入口不再重放该补丁，补丁文件仅作历史记录。
