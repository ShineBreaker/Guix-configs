---
name: agenote-review
description: 会话后经验采集与留痕。**触发信号**：agenote-hooks 插件检测到完成信号 / 用户触发 `/agenote-summarize` / 长任务结束前的例行评估 / 用户纠正了你 / 排查 >2 步才定位根因 / 发现了比初始方案更优的写法。**当上述任一信号出现时立即调用本 skill** 做"经验信号识别 + ENTRY_TYPE 判定 + 留痕决策树"，按其内部规则写卡片或 touch 已有卡片。基础用法见 `agenote-base`。
---

# agenote-review — 会话后经验采集与留痕

会话结束时（或检测到完成信号时），评估是否有可记录的经验，并对用到的资料留痕。

> agenote 已改造为 MCP server，以下 `agenote_*` 均为 MCP tool 名。底层 CLI 为 `agenote`（`~/.local/bin/agenote`），默认操作 agenote 子库（与 MCP server 对齐），`--domain human` 切到人类知识库根。

## 触发时机

- agenote-hooks 插件检测到完成信号（见 [references/triggers.md](references/triggers.md)）
- 用户主动 `/agenote-summarize`
- 长会话结束前的例行评估

## 任务前预检

<critical>
开始任何非平凡任务前，必须先执行 `agenote list --category <category> --all` 读取对应领域标题索引；每次都必须做。标题列表不足以定位时，再执行 `agenote search` 正文预检。
</critical>

```
agenote list --category <相关类别> --all
agenote get <明显相关的卡片ID>
agenote search "<当前任务的关键技术 工具 症状>"
agenote profile
```

**必须预检**：调试/排障、配置修改、已使用过的技术栈、与之前类似的问题。
**可跳过**：全新领域开发、简单编辑、有明确文档的标准操作。

**结果处理**：高相关 → 作为上下文参考；低相关/空 → 静默继续；矛盾 → 以较新/经验证的为准。

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

## 轻量写入

不是所有经验都值得写完整卡片：

| 目标           | 方式                                        | 条件                           |
| -------------- | ------------------------------------------- | ------------------------------ |
| 可复用技术经验 | `agenote add` 完整卡片                      | 排查 >2 步、跨工具、架构决策   |
| 偏好/习惯      | `agenote memory --add`                      | 偏好表达、行为纠正             |
| 一句话注意     | `agenote inbox` / `agenote update --append` | 简单修正、补充                 |
| 不写           | —                                           | 一次性细节、环境失败、否定声明 |

优先级：纠正(mistake) > 调试(debug/config) > 工作流 > 功能

## 可记录信号清单

### 经验信号（触发 add）

- **用户纠正**：用户指出 agent 的错误（"不对"、"应该是"、"重新做"）
- **踩坑**：agent 遇到报错、卡住、反复调试
- **更优方案**：发现比当前做法更好的方式
- **项目决策**：确定某技术选型、架构方向

### 完成信号（触发本评估流程）

完整清单见 [references/triggers.md](references/triggers.md)（agenote-hooks 插件单一真相源）。

## 记忆信号（写入 MEMORY.org）

| 信号类型 | 记忆类型  | 关键词/信号                          | 写入命令                                             |
| -------- | --------- | ------------------------------------ | ---------------------------------------------------- |
| 偏好表达 | feedback  | "我喜欢..."、"不要..."、"停..."      | `agenote memory --add --type feedback`               |
| 行为纠正 | feedback  | 用户纠正了你的工作方式（非技术错误） | `agenote memory --add --type feedback`               |
| 习惯模式 | feedback  | 同一偏好出现 ≥2 次                   | `agenote memory --add --type feedback`               |
| 项目决策 | project   | 不可从代码推导的项目级决策/状态      | `agenote memory --add --type project --project <id>` |
| 外部指针 | reference | 外部系统/文档/资源的位置信息         | `agenote memory --add --type reference`              |

**MEMORY vs KB 边界**：

- "你怎么做"（风格/流程/工具选择偏好）→ MEMORY
- "你做错了"（事实/技术错误）→ KB
- 两者可能并存：同一事件同时写入 MEMORY 和 KB

**防误触发**：

- 技术性纠正（"正则写错了"、"参数传反了"）→ 只写 KB，不写 MEMORY
- 普通确认（"好的"、"行"）→ 不触发任何系统

## 写入时机

**必须写入**：非显而易见的 bug（排查 >2 步）、环境特殊行为、配置踩坑、用户纠正。

**不必写入**：语法拼写修正、文档有明确答案、一次性操作、已有经验覆盖、用户仍在纠正中。

## 写入流程

1. `agenote search` 去重
2. 矛盾检测 — 新发现是否与已有卡片/pattern 矛盾
3. `agenote fields` 查看标签，优先复用
4. `agenote add` 写入卡片（CLI 用法见 `agenote-base` skill）
5. `agenote lint` 校验格式
6. 传播联动 — 检查受影响的 pattern/卡片
7. `agenote connect` 建立关联链接
8. `agenote profile --add` 更新画像（如涉及偏好/项目变化）

### MEMORY 写入流程

1. 判断信号类型（偏好/行为纠正/习惯 → feedback，项目决策 → project，外部指针 → reference）
2. `agenote memory --add --type <type> [--project <id>] --title "标题" --stdin <<EOF` 正文 `EOF`
3. feedback 类型：自动分配 F 序号，插入 MEMORY.org `* feedback` 节
4. project 类型：自动追加到 memories/projects/<name>.org 对应节
5. reference 类型：自动分配 R 序号，插入 MEMORY.org `* reference` 节

### 增量更新原则

- **任务完成后立即触发** — 不要累积多个任务后再统一总结
- **小步快跑** — 一个任务一张卡片，不要把多个不相关经验塞进一张卡片
- **即时回顾** — 写入后快速浏览相关卡片，确认新经验是否与已有知识形成有效连接

### `mistake` 卡片必须覆盖

1. 原始问题
2. 用户纠错反馈链
3. 这次错在哪里
4. 最终正确处理
5. 下次自检
6. 不确定结论标注 `(推测)`/`(单源)`，可能过时标注验证日期

### `note` 卡片必须覆盖

1. 事项内容
2. 为什么值得长期保留
3. 适用场景和边界
4. 后续行动

## 写入规范

### 写入前决策

1. `agenote search` 去重 — 已有卡片覆盖时补充修正，不新建重复卡
2. **优先复用已有标签** — `agenote fields` 查看现有 category/tech，只有全新领域才创建新类别
3. 项目私有细节只写必要上下文；可泛化规则晋升到 pattern
4. 卡片保存完整过程，pattern 保存紧凑规则；二者可共存，pattern 必须引用卡片 ID

详见 [references/writing-guide.md](references/writing-guide.md) 和 [references/ai-first-rules.md](references/ai-first-rules.md)。

### Entry type 映射

| 来源语义     | `--entry`  | 推荐 type             | 推荐 owner      |
| ------------ | ---------- | --------------------- | --------------- |
| 用户纠错     | `mistake`  | `debug` / `config`    | `collaborative` |
| 长期注意事项 | `note`     | `workflow` / `config` | `ai`            |
| 飞升模式复盘 | `ascended` | `debug` / `workflow`  | `collaborative` |

## 卡片生命周期

```
done → stable(策展验证) → stale(>30天未验证) → archived(>90天)
```

- `agenote touch <id>` — 标记"刚用过"
- `agenote update <id> --status stable` — 策展后设为 stable
- `agenote archive <id>` — 归档
- `agenote restore <id>` — 恢复
- `agenote review <id>` — 审查卡片质量

## 模式归纳

同类经验 ≥3 次 → 晋升为 pattern。晋升不删除原卡片。

**模式结构**（≤5 行）：

```
** <结论性标题>
   <一句话声明式规则>。
   适用：<场景>
   例外：<反例或边界条件>
   参考：<经验卡片 ID>
```

**模式即时修补**：使用 pattern 时发现过时/不完整/有误，必须立即修补，不要等待用户提醒。

## 回顾机制

定期（建议每月）执行以下回顾：

1. **知识内化检查** — 浏览最近 10 张卡片，问自己：这些经验是否已成为默认行为？
2. **模式有效性** — 检查 patterns.org 中的模式，是否有已被新实践推翻的？
3. **连接补全** — 扫描孤立卡片（无 connect 链接），评估是否需要建立关联
4. **画像更新** — 检查 profile.org 是否反映当前真实偏好和项目状态

回顾可手动执行，也可由 `agenote-curator` skill 在后台策展时一并完成。

## 飞升模式

同一问题被纠正 ≥2 次仍无法解决 → 进入飞升模式。

核心：全面检索知识源 → 筛出最接近经验 → 解释失败原因 → 给出最强方案 → 写入经验卡片。

详细步骤见 [references/ascended-mode.md](references/ascended-mode.md)。

## 用户画像维护

### 触发条件

- `profile.org` 的 `#+date` 距离当前日期超过 **7 天**
- 经验写入流程第 8 步中发现用户的**偏好变化**或**活跃项目变更**

### 分类体系

固定 5 个一级分类：**身份** / **偏好** / **习惯** / **活跃项目** / **目标**

### CLI 操作

```
agenote profile                                 # 概览
agenote profile <分类名>                        # 查看指定分类
agenote profile --add "目标" --text "..."       # 追加条目
echo "- 新内容" | agenote profile --set "偏好"  # 覆盖分类
```

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

## 详细参考

- [经验信号检测触发器](references/triggers.md) — 完整信号清单
- [写入决策树](references/write-decision.md) — 轻量 vs 完整卡片
- [轻量写入模式](references/lightweight-writing.md) — 快速捕获与补充
- [写作指南](references/writing-guide.md) — 传播联动、自包含、时效性、矛盾检测
- [AI-First 卡片规则](references/ai-first-rules.md) — 自包含上下文、摘要、置信度标注
- [飞升模式详解](references/ascended-mode.md)
