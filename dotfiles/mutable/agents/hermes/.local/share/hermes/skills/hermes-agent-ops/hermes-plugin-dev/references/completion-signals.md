# Completion Signals (single source: agenote-review/references/triggers.md)

与 `pi-agenote/index.ts:COMPLETION_SIGNALS` 保持一致，收紧到强完成词（避免“好了”等高频误触）：

```
可以用了, 一切正常, 都没问题, 都正常, 搞定, 完成, 做完了, 测试通过,
就这些, 先这样, 暂时够了, 就这样, 没了,
done., done!, looks good, ship it
```

检测：`any(sig.lower() in text.lower() for sig in SIGNALS)`。改动时同步 `agenote-review/references/triggers.md` 与本插件 `COMPLETION_SIGNALS`。
