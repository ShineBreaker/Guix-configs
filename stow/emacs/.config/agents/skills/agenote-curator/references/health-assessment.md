# `agenote` 健康度评估范式

> 何时用：用户问"agenote 效果如何"、"知识库怎么样"、"是不是该引进新系统"、"为什么 agent 不爱用"时，先跑这一套体检再回答。

## 体检四件套（必走，按顺序）

```bash
# 1. 总量 + 类别/类型/owner 分布（30 秒出）
kb agenote stats

# 2. 健康度指标 + 红色告警（核心）
kb agenote health

# 3. 列表全量（看实际写了什么）
kb agenote list

# 4. MEMORY.org 4 个分栏（feedback / project / reference / deprecated）
cat ~/Documents/Org/agenote/MEMORY.org
```

## 健康度指标解读

| 指标         | 阈值              | 含义                          | 修复动作                                                                   |
| ------------ | ----------------- | ----------------------------- | -------------------------------------------------------------------------- |
| **孤立率**   | <15% ✅ / <25% ⚠️ | 无 `[[file:]]` 链接的卡片占比 | `kb agenote connect <id1> <id2>` 双向关联，或 `kb agenote curate` 自动     |
| **过时率**   | <10% ✅ / <20% ⚠️ | stale 状态卡片占比            | `kb agenote archive --stale`（默认 30 天）                                 |
| **类型偏斜** | <45% ✅           | 单一 type 占比过高            | 缺 `ascended`/`mistake` 时引导用户补充；`kb agenote curate --type-balance` |
| **薄弱类别** | ≥3 ✅             | 每个类别至少 3 张卡片         | 新增卡片时分散到薄弱类别                                                   |

## 三个"红灯组合"信号

体检结果同时命中以下任意两条，就是"地基打好但房子没盖"状态：

1. `孤立率 > 80%` → 卡片互相不引用 = 没形成知识网络
2. `feedback: 0` 或 `project: 0`（看 MEMORY.org） → 跨会话偏好/项目元数据没沉淀
3. `usage_count: 0`（全量卡片） → 写了没人读 = 入库动作和检索动作断链

**根因诊断**：

- 红灯组合 + 总数 < 20 → **写入侧断链**：用户/agent 没有主动 add 卡片
  - 检查是否有 `agenote-hooks` 插件（pi 才有）
  - 检查 `agenote-review` skill 是否被加载
- 红灯组合 + 总数 > 50 → **读取侧断链**：写了但检索质量差或没人 query
  - 检查 `kb agenote search` 是否被各 agent 调用
  - 考虑加 MCP 暴露（让 agent 协议级 query）

## 输出报告骨架（用户问"agenote 怎么样"时直接套）

```
1. 健康度总览（贴 kb agenote health 输出）
2. 三个红灯命中？（是/否，命中哪几个）
3. 根因（写入侧断链 / 读取侧断链 / 类型偏斜）
4. 推荐动作（按优先级列 3-5 条具体命令）
5. 不推荐：换新系统 / 引入 Mem0 / Honcho / AgentMail（除非有强需求）
```

## 反模式（体检时常踩的坑）

- ❌ **只看 `stats` 总数就回答**——5 张卡片健康和 500 张卡片健康含义完全不同，必须看 `health`
- ❌ **建议立刻 `kb agenote curate`**——`curate` 会自动归档 stale + 重排权重，**只在你确定健康基线后再跑**；否则会把"刚写的待沉淀卡片"误归档
- ❌ **建议换新系统**——99% 的情况下不是系统问题，是写入/读取侧断链
- ❌ **不查 `MEMORY.org`**——`feedback: 0` + `project: 0` 是双轨不通的根因，必须显式提
