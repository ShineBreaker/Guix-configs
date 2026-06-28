---
name: agenote-review
description: 会话后经验采集与留痕指南。当检测到任务完成信号、需要评估本次对话是否有可记录经验、或对用到的资料留痕时使用。涵盖可记录信号识别、ENTRY_TYPE 判定、留痕决策树。
---

# agenote-review — 会话后经验采集与留痕

会话结束时（或检测到完成信号时），评估是否有可记录的经验，并对用到的资料留痕。

> agenote 已改造为 MCP server，以下 `agenote_*` 均为 MCP tool 名。

## 触发时机

- agenote-hooks 插件检测到完成信号（见 [triggers.md](references/triggers.md)）
- 用户主动 `/agenote-summarize`
- 长会话结束前的例行评估

## 评估决策树

```
本次对话是否有可记录的经验信号？
│
├─ 是 → 判断 ENTRY_TYPE
│   ├─ 用户纠正/走弯路/误判 → agenote_add(entry="mistake", ...)
│   ├─ 查到的有用知识/方案 → agenote_add(entry="note", ...)
│   └─ 多轮试错后的最优方案 → agenote_add(entry="ascended", ...)
│
└─ 否 → 还要评估"留痕"
    │
    本轮用到了哪些外部资料？
    ├─ 来自 agenote/人类KB 的已有卡片 → agenote_touch(target="<ID>")
    └─ 来自联网的新知识
        ├─ 已确认有用（实际应用到代码/答案）→ agenote_add(type="note", ...)
        └─ 仅浏览未采用 → 不记录（避免噪音）

如果既无经验信号、又无留痕需求 → 明确回复"本次无可记录经验"
```

## 可记录信号清单

### 经验信号（触发 add）

- **用户纠正**：用户指出 agent 的错误（"不对"、"应该是"、"重新做"）
- **踩坑**：agent 遇到报错、卡住、反复调试
- **更优方案**：发现比当前做法更好的方式
- **项目决策**：确定某技术选型、架构方向

### 完成信号（触发本评估流程）

见 [references/triggers.md](references/triggers.md)（agenote-hooks 插件的单一真相源）。

## 留痕操作

### 对已有卡片留痕（复用）

当本次会话引用/使用了某张已有卡片（人类的或 agenote 的）：

```
agenote_touch(target="<ID>")           # 递增 USAGE_COUNT + 更新 LAST_USED
# 或读取时顺手留痕：
agenote_get(target="<ID>", used=true)
```

> 注意：先用 `agenote_search` 或 `agenote_list` 找到卡片 ID（get/touch 用 ID 匹配，不是 title）。

### 对联网新知识留痕（首次获取）

```
agenote_add(
    title="<知识标题>",
    type="note",
    entry="note",
    body="来源: <URL/API>\n核心结论: ...\n适用场景: ..."
)
```

## 避免噪音

- **纯浏览未采用**的资料不记录
- **临时调试输出**、可从代码直接推导的信息不记录
- **一次性任务**、不具复用价值的细节不记录
- note 卡片由 agenote-curator 定期 dedup（避免同一知识多次联网各记一条）

## 与 memory 系统的边界

- **卡片（experiences/）**：记"某次具体事件/知识"——有明确时间点
- **memory（MEMORY.org）**：记"跨会话偏好/项目元数据"——持续性
- 用户偏好 → `agenote_memory_add(mem_type="feedback", ...)`
- 项目约束 → `agenote_memory_add(mem_type="project", project="<名>", ...)`
