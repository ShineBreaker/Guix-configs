---
name: correction-funnel
description: "任务结束（success 或 fail）时，强制跑 correction funnel：1) 跑 `agenote_dream` 拿 correction 候选 → 2) 主会话 review 候选判 'local-only / durable judgment' → 3) 入 KB (`agenote_add` 或 `memory`) 或丢弃 → 4) 留痕到 curator_state。来源 punkjazz.ai §05 'What survives the task'——correction 影响 future behavior after review。触发词：'任务总结 / correction funnel / 把教训沉淀 / 入 KB / 入 memory / 这次任务学到了什么 / 留痕 / 提炼经验 / dream / KB 写入'，或在 task-contract 任务收尾阶段。"
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [correction-funnel, kb, memory, agenote, post-task, learning]
    related_skills: [task-contract, adversarial-review-trigger, agenote-base, agenote-curator]
---

# correction-funnel — 任务结束后的修正沉淀

## 核心命题

**correction 影响 future behavior after review**。来源 punkjazz.ai §05：

> The useful output from that failure extended beyond the repaired code. The system gained new tests, a safer lifecycle, a transactional update process, and a standing policy that requires protected actions to receive authority from outside the agent process. Those changes now apply before the next agent reaches the same category of decision.
>
> This is where cognition and execution meet. The execution loop handles the current task, records its evidence, and exposes a correction. **The cognition layer decides whether that correction belongs only to this project or should become durable judgment.** Independent review helps prevent an isolated mistake or an over-broad lesson from turning into a permanent rule.

**关键点**：

- 不是所有 correction 都进 KB——只有 **durable** 的进
- 进 KB 前必**独立 review**——防"局部错误变成永久规则"
- **local-only** 的不进 KB（项目专属，不值得跨项目学习）
- 不沉淀 = 重复犯同一个错

## 何时使用（trigger）

满足以下**任一**条件：

- task-contract 任务**收尾阶段**（success 或 fail 都跑）
- adversarial review 找到了 false-success（correction 真出现）
- 用户说"这次任务学到了什么" / "留个教训" / "沉淀"
- 主会话识别到这是一个**可复用的 pattern**，而不仅是一次性修复

不适用：

- 单文件 typo / README
- 查询 / 闲聊任务
- 已经在 KB 里的同一个 correction（先 search 再 add）

## 工作流程（5 步）

### Step 1: 触发 + 收口

```bash
# 任务结束 → 主会话问自己:
# "这次任务有什么 reusable lesson?"
```

**重要**：先**写下来**（在 todo notes 里），不要直接进 Step 2。

### Step 2: 跑 `agenote_dream` 找候选

```bash
mcp_agenote_agenote_dream(
    window_days=90,  # 90 天窗口覆盖 ~90% facts
    limit=5,
)
```

返回的每个候选含 `source_trace` 字段（= fact_id），是溯源指针。

**不要直接调用 dream 把候选转 KB** —— dream 是**只读候选发现器**，绝不在 KB 里写任何东西（这是 agenote-curator skill 的设计约束）。

### Step 3: 评估 candidate → 3 个判定

对每个 candidate，主会话**逐条**判断：

| 判定 | 含义 | 处理 |
|------|------|------|
| **durable** | 跨项目、跨任务可复用 | 进 Step 4（写 KB） |
| **local-only** | 仅当前项目 / 当前 config | 丢弃（不进 KB） |
| **duplicated** | 已经在 KB 里 | 丢弃（标注已覆盖） |

**判定启发**（来自 punkjazz.ai）：

- "这个 lesson 在另一个项目里也成立吗？" → 否 → local-only
- "这个 lesson 已经被另一个 KB 卡片覆盖了吗？" → 是 → duplicated
- "这个 lesson 是品味 / 个人偏好 还是技术事实？" → 品味 → local-only（个人偏好已通过 memory tool 处理）
- "这个 lesson 是不是孤立的失败（一次失误）？" → 是 → local-only（防 over-broad lesson）

### Step 4: durable candidate → 入 KB

```bash
mcp_agenote_agenote_add(
    title="<lesson 标题>",
    entry="note|mistake|ascended",  # 决定正文模板
    category="<已有 category>",
    tech="<技术栈>",
    type="workflow|debug|knowledge|...",
    summary="<一句话总结>",
    body="<详细内容，含 evidence + 决策逻辑>",
)
```

**entry 选择**：

- `note`：观察到的事实/模式
- `mistake`：踩过的坑 + 怎么避
- `ascended`：多次失败后找到的正确做法

**关键约束**（agenote-curator §3）：

- 标题简洁、描述可搜
- body 含 evidence（命令输出、commit hash、错误信息）
- body 含**为什么**（不只是**怎么做**）
- entry 选择要诚实（mistake 不掩饰，ascended 不夸大）

### Step 4b: durable **个人偏好** → memory tool

如果 candidate 是**用户偏好**（不是技术事实）：

```bash
memory(
    action="add",
    target="user" 或 "memory",
    content="<用户偏好陈述>",
)
```

判断标准（来自 MEMORY.md 用户硬约束）：

- 用户偏好 → `target=user`
- 环境事实 / 工具约定 → `target=memory`
- 项目专属 → `fact_store` (按需检索，不入 markdown)

### Step 5: 留痕 + 闭环

```bash
# 跑 agenote_curate（轻量，不需要 LLM）
# 不需要每次跑，但重大 correction 跑一次能加速索引 / 去重 / 健康度
mcp_agenote_agenote_curate()
```

回报给用户：

- "correction funnel: durable 入 KB N 条 / local-only M 条 / duplicated K 条"
- 列 durable 的标题
- 如果有"过度 broad"的 lesson（如 `rm` 全面禁用），明确说明保留范围

## 防 over-broad lesson 的硬约束

punkjazz.ai 强调**独立 review** 防 over-broad。本 skill 落地为：

- 进 KB 前**主会话自查**："这个 lesson 在另一个项目里也成立吗？"
- 如不确定 → **不写 KB**，写到 conversation 里给用户看（让用户拍板）
- 不写**未经 evidence 证实的教训**——只写有 commit / 命令输出 / 文件路径佐证的

## 与其它 skill 的接口

- **`task-contract`**：任务**结束**触发 correction funnel（task-contract 的核对清单对应 Step 4 的 evidence）
- **`adversarial-review-trigger`**：找到的 finding → correction funnel
- **`agenote-base`**：KB 写入的 protocol
- **`agenote-curator`**：KB 健康度 / 周期 curate
- **`memory` tool**：用户偏好（不是技术事实）的另一通道

## 不做的事

- ❌ 不每任务都跑 agenote_curate（频率约每周）
- ❌ 不把品味 / 个人偏好 / 一次失误写进 KB
- ❌ 不跳过 independent review 直接入 KB（防 over-broad）
- ❌ 不覆盖已有 KB 卡片（先 search 再 add）

## References

- `references/agenote-write-patterns.md` — 哪些 entry 类型适合什么 lesson
- `references/example-funnel-run.md` — 真实 correction funnel 跑通的样本

## Out of scope

- 任务**进行中**的 adversarial review → `adversarial-review-trigger`
- 任务**开始前**的契约 → `task-contract`
- KB 健康度周期 curate → `agenote-curator`