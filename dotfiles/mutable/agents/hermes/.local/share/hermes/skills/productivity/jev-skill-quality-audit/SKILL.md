---
name: jev-skill-quality-audit
description: "Audit Hermes skill descriptions with Jev. Read-only."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [jev, skill-audit, quality, curator, typesafe, description-quality]
    related_skills: [corpus-quality-audit, hermes-skill-curation, agent-config-metabolism]
---

# Jev 审 Hermes 自建 skill

对 `$HERMES_HOME/skills/` 下的自建 skill 做**只读**语义质量判定，输出排序表。判定引擎是 TypeSafe 的 Jev（`evaluateJev`，POST `https://api.typesafe.ai/v1/systemone`，key 走 `TYPESAFE_API_KEY`）。

本 skill 是 `hermes curator` 的**语义预筛层**，不是决策层：curator 的确定性 pass 管时间轴（多久没用→归档），LLM pass 管合并；Jev 补的是两者都不看的内容维度。**永远不写 skill 文件**，产出就是报告。

## When to Use

- 周检时想顺带看一眼 skill 库的语义质量（并入 `agent-config-metabolism` 周检流程）
- `hermes curator run --consolidate` 之前，想先圈定「合并候选」和「需要重写 description 的」
- 怀疑某个 skill 的 description 触发类写得太窄/太宽，导致 loader 发现不了

## 硬规则

1. **只读**。本 skill 的任何流程都不调用 `skill_manage` / `patch` / `write_file` 改 skill。要改自己来，或显式交给 curator。
2. **判定输出不是事实**。Jev 主训练语言英文，CJK 语料绝对精度受限；只信**相对排序**，且排序要先经交叉验证（见下）。
3. **不问主观质量**。「值不值得读」「信息量多少」这类问题 Jev 给平滑连续值、没有决策边界，头部与中部只差 0.2，问了等于白问。只问有客观判据的硬问题。
4. **一次请求一条 skill**。Jev 的 `state` 即使给数组也只当整体语境处理、`answers` 不逐元素展开（twitter-digest 实测），批量时必须逐条 POST。
5. **超长 SKILL.md 截断要标注**。保留头部（规则与触发类在头部），在 state 里写明「first N of M chars, TRUNCATED」，否则模型会把片段当全文。

## 问题集（4 问，一次请求批量返回）

| id | 类型 | 问什么 | 有信号的用法 |
| --- | --- | --- | --- |
| `trigger_class` | noul | description 是否写明**可判定的触发条件**，而非只命名主题 | <0.80 进「description 待重写」清单 |
| `stale_facts` | noul | 是否含版本号/接口行为等**易被新事实取代**的内容 | >0.70 且近期无 patch → 提示人工复核 |
| `has_rules` | noul | 有没有可执行规则，还是只有叙述和例子 | 校准用（健康 skill 恒 ~0.99，无分辨力） |
| `single_session` | noul | 内容是否只属于一次会话，无类级规则 | 校准用（恒 ~0.02，无分辨力） |

`has_rules` / `single_session` 保留在脚本里只为**校准**：它们在健康 skill 上恒定贴在两端，说明模型读懂了文档类型，但不构成排序依据。真正驱动清单的只有前两个。

`noul` 返回 0~1 概率；`score` 返回 0~2 **连续置信度**，不是三档离散分。阈值是连续值比较，别把 0.5 当精确边界。

## 跑法

```bash
python3 $HERMES_HOME/skills/productivity/jev-skill-quality-audit/scripts/jev_skill_audit.py \
    [--root $HERMES_HOME/skills] [--all] [--names a b c] [--out report.md]
```

- 默认读 `$HERMES_HOME/skills/.usage.json`，只审 curator-managed 且 `state != archived` 的 skill
- `--all` 审磁盘上全部 SKILL.md（含 unmanaged / bundled）
- `--names` 指定单个 skill 名做抽查
- 输出 stdout 表格 + `--out` 落一份 markdown 报告

密钥从环境变量 `TYPESAFE_API_KEY` 读；缺失时脚本早失败并提示从 `$HERMES_HOME/.env` 取。

## 交叉验证（放量前必做）

拿本地已知极性样本跑 8~12 条，看分不分得开：

- 近期被频繁 patch 的高维护 skill（`hermes curator status` 的 most active 列表）→ `trigger_class` 应落在高档
- 纯流程性、一次性的 skill → `stale_facts` 应显著更高
- 两者拉不开 → 改问题表述，问更硬的判据，**不要**带着疑点出报告

分不开的常见原因：问的是主观质量（回到硬规则 3），或 state 截断把 description 之后的规则全丢了。

## 报告怎么读

```
trigger_class < 0.80   → description 触发类不可判定，loader 可能根本发现不了这个 skill
stale_facts  > 0.70    → 版本绑定内容，人工读一遍确认是否仍成立
两者同时命中          → 优先重写，成本最低收益最大
```

报告只给清单和依据，**不自动执行任何修改**。要不要重写、要不要合入 curator 的 umbrella pass，由人或 `hermes curator run --consolidate` 决定。

## 与 curator 的分工

| 维度 | 谁管 |
| --- |
| 多久没用 → stale / archive | `hermes curator` 确定性 pass（`.usage.json` 时间轴） |
| 该不该合并成 umbrella | `hermes curator` LLM pass（`curator.consolidate: true`） |
| description 触发类质量、版本绑定风险 | **本 skill** |
| 相似度 / 聚类 / 去重候选 | 确定性算法（共享实词、标题相似度）——Jev 在成对相似度上偏保守，拿它判「该不该连边」会系统性漏连 |

## Pitfalls

- **别用 Jev 判「该不该合并」**。它给的是质量/特征置信度，成对相似度偏保守（两个明显同主题的 skill 可能只给 0.39）。合并判断交给 curator 的 LLM pass 或人。
- **别把校准维度当排序依据**。`has_rules` 恒高、`single_session` 恒低是模型的文档类型理解，不是质量信号；照它们排序会得到一份没有信息量的榜单。
- **token 成本先估**。全库约 `skill 数 × 2.5K input tok`（69 个约 170K），跑前用 3~5 个样本实测再放量。
- **`.usage.json` 里 `state: archived` 的 skill 默认跳过**。要审它们显式传 `--all`。
- **cron 引用 / pinned 的 skill 照审**，但报告里标出来——它们的生命周期由 curator 另行保护，语义结论只作参考。

## References

- `references/judgment-api-integration.md` — Jev 请求构造的三个陷阱（settings 值域、`undefined` 被拒、超长 state 截断）、question 设计原则、什么该问 Jev 什么该用确定性算法。与 `corpus-quality-audit` 同源，改动需同步两边。

