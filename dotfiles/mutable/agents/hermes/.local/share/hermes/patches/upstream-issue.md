# Upstream issue: include fact_id in prefetch injection lines

- **状态**: 文案就绪，待用户在 GitHub 提交（agent 无 gh 认证时的降级路径；若本机 gh 已认证可直接 `gh issue create`）
- **仓库**: https://github.com/NousResearch/hermes-agent
- **创建后**: 把 issue 链接回填到 plans/2026-08-29-general-assistant.md §2.1

## Title

feat(memory): include fact_id in prefetch injection lines for feedback-loop closure

## Body

The holographic memory provider's `prefetch()` (plugins/memory/holographic/__init__.py, line ~214) injects a per-turn context block formatted as:

```
- [trust] content
```

while `fact_feedback` — the only path that drifts `trust_score` — requires `fact_id` as a mandatory parameter. The prefetch channel is the majority of actual retrieval traffic (top-5 injected every turn), yet the facts it surfaces are structurally un-ratable: the model sees them but has no handle to feed back on them. Result: the trust-training loop never fires for passive recall, and `final_score = relevance * trust` degenerates to pure relevance ranking with all facts stuck at 0.5.

Related finding (same investigation): `retrieval_count` only increments in `store.search_facts()`, which has zero production callers — both the prefetch path and the `fact_store` tool's search action go through `FactRetriever.search()` (retrieval.py:48), which does direct SQL and skips the counter. So `retrieval_count` is a dead metric that says nothing about whether retrieval happens.

### Proposal

Include the fact id in the injection line:

```python
lines.append(f"- [{trust:.1f}] (#{r.get('fact_id', '?')}) {r.get('content', '')}")
```

One-line diff, attached below. Locally verified: after the patch, trust drift works end-to-end (rated a stale fact unhelpful, 0.5 → 0.4) and the feedback loop fires on passive recall too.

### Patch

```diff
diff --git a/plugins/memory/holographic/__init__.py b/plugins/memory/holographic/__init__.py
--- a/plugins/memory/holographic/__init__.py
+++ b/plugins/memory/holographic/__init__.py
@@ -211,7 +211,7 @@ class HolographicMemoryProvider(MemoryProvider):
             lines = []
             for r in results:
                 trust = r.get("trust_score", r.get("trust", 0))
-                lines.append(f"- [{trust:.1f}] {r.get('content', '')}")
+                lines.append(f"- [{trust:.1f}] (#{r.get('fact_id', '?')}) {r.get('content', '')}")
             return "## Holographic Memory\n" + "\n".join(lines)
         except Exception as e:
             logger.debug("Holographic prefetch failed: %s", e)
```
