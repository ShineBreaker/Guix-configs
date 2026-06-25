# 任务完成信号清单

> **单一真相源**：agenote-hooks 插件（`stow/pi/.config/pi/extensions/agenote-hooks/index.ts` 的 `COMPLETION_SIGNALS` 常量）以此文件为准。改动此处需同步插件 TS 代码。

这些信号词出现在用户消息中时，agenote-hooks 插件会注入 agenote-review 评估提示。信号已收紧到"强完成词"，避免"好了"等高频日常词误触发。

## 中文显式完成

- 可以用了
- 一切正常
- 都没问题
- 都正常
- 搞定
- 完成
- 做完了
- 测试通过
- 通过
- 就这些
- 先这样
- 暂时够了
- 就这样
- 没了

## 英文显式完成

- done.
- done!
- looks good
- ship it

## 调整原则

新增/删除信号时：

1. 修改本文件
2. 同步 `agenote-hooks/index.ts` 的 `COMPLETION_SIGNALS` 数组
3. 优先用"明确无歧义"的完成词，避免高频词
