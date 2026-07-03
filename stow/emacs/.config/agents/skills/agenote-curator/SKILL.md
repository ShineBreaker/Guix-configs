---
name: agenote-curator
description: 跨 agent KB 健康度维护。**触发信号**：每周/长会话后例行维护 / 卡片 >50 张 / 检索质量明显下降 / 用户触发 `/agenote-curate` / 发现重复卡片或矛盾结论 / 新增了对话抽取源。**当上述任一信号出现时立即调用本 skill** 做健康检查+去重+归档+权重重分配+reconcile 多源 memory。基础用法见 `agenote-base`；会话中单次经验记录见 `agenote-review`。
---

# agenote-curator — 跨 agent 自动策展

定期对 agenote 记事本执行策展，保持健康度并优化检索权重；同时支持从多个 AI 编程工具抽取对话、跨 agent reconcile 多源 memory。

> agenote 已改造为 MCP server，以下 `agenote_*` 均为 MCP tool 名。底层 CLI 为 `agenote`（`~/.local/bin/agenote`），默认操作 agenote 子库（`~/Documents/Org/agenote/`，与 MCP server 对齐），`--domain human` 切到人类知识库根。

## 何时策展

- 周期性维护（每周/每次长会话后）
- 条目数明显增多（>50 张）
- 检索结果质量下降（噪音多、相关性差）
- 新增了对话源或更新了 XDG 环境变量
- 用户主动要求 `/agenote-curate`

## 一键策展（MCP 流水线）

```
agenote_curate()
```

执行 **2 阶段**：

### Step 1 — KB 内策展（5 步）

1. **健康检查**：孤立率、过时率、类型偏斜、薄弱类别
2. **权重重分配**：根据 USAGE_COUNT 和新鲜度重新计算每张卡片的 WEIGHT
3. **去重检测**：标题相似度 + category/tech 匹配
4. **归档陈旧**：超阈值（90 天）未验证的 stale 卡片自动归档
5. **重建索引**：全量扫描 experiences/ 刷新 index.json

### Step 2 — 跨 agent reconcile

按 `ag_lib/extract/__init__.py` 的 `_resolve_extractors()` 注册顺序跑全部 source，结果写到 `.reconcile/index.json`。

## Batch 策展流水线（`kb` CLI）

按顺序执行以下 10 步，适用于夜间策展或手动批处理：

### 第 0 步：提取对话

```bash
# MCP tool（agent 主循环用）：agenote_extract(source="all")
# CLI 等价（底层走 ag_lib/extract/ 多源抽取器）：
agenote extract --source all --output ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)
```

> 注：`agenote extract` 子命令尚未在 CLI 暴露（抽取逻辑在 `ag_lib/extract/`，当前仅通过 `agenote_extract` MCP tool 调用）。CLI 批处理场景请用 MCP tool，或直接调 `python3 -m ag_lib.extract`。

### 第 1 步：诊断

```bash
agenote health --quality --duplicates   # 健康度 + 质量扫描 + 重复检测（统一自 ag_lib/health.py）
agenote stats                           # 状态分布
```

### 第 2 步：状态转换

```bash
# done >30 天且质量合格 → stable
agenote update <id> --status stable
# stale >90 天 → 归档
agenote archive <id> --reason "策展: >90 天未验证"
```

### 第 3 步：空白检测

```bash
agenote gaps --stale-days 60            # 类别×类型矩阵 + 缺失组合 + 陈旧卡片（迁自 find_gaps.py）
```

### 第 4 步：矛盾调和

见下方"矛盾调和规则"。

### 第 5 步：自发综合 + 卡片合并

```bash
agenote deduplicate --threshold 0.7
agenote merge <primary> <secondary> --desc "合并原因"
```

### 第 6 步：补充

从对话历史/收件箱提取经验：

```bash
agenote fields        # 查看标签，优先复用
agenote add ...       # 写入新卡片
```

### 第 7 步：传播联动

见下方"传播联动规则"。

```bash
agenote memory --stale                    # 记忆验证
agenote memory --stale --auto-archive-days 60  # 自动归档
```

### 第 8 步：重整

```bash
agenote reindex
agenote lint --fix
```

### 第 9 步：提交变更

```bash
agenote commit -m "策展: <一句话总结>"
```

commit message 要求：以 `策展:` 前缀开头，50 字以内总结核心操作（新增 K 张 / 更新 M 张 / 晋升 P 条）。无变更时跳过。

### 第 10 步：输出报告

格式见下方"报告格式"。

## 策展原则

**应记录**：用户偏好和纠正、非显而易见的 bug（排查 >2 步）、环境特定陷阱、更好的方案。

**不应记录**：任务进度和 TODO、语法错误和拼写修正、纯流水账、已有经验完全覆盖的情况。

**维护理念**：过时卡片是负担不是资产、矛盾必须处理、卡片之间应有链接。

## 矛盾调和规则

| 矛盾类型           | 处理                              |
| ------------------ | --------------------------------- |
| 同条件相反结论     | 保留较新的，旧卡标注「已过时」    |
| 不同条件分别成立   | 互相引用，注明各自适用场景        |
| 旧方案被取代       | 旧卡标注「已被 \<新卡ID\> 取代」  |
| pattern 与卡片矛盾 | 修补 pattern，标注修订原因        |
| 歧义未决           | 双方标注 `(存疑)`，待下次策展验证 |

## 传播联动规则

- 新卡片推翻旧结论 → `agenote update` 在旧卡追加勘误
- 同类卡片 ≥3 张 → 晋升为 pattern
- 新卡片补充了已有 pattern → 修补 pattern
- 隐含关联的卡片 → `agenote connect` 建立双向链接
- pattern 引用的卡片已过时 → 标注 pattern 并引用新卡片

## Andon 机制（策展暂停）

后台策展过程中发现以下情况时，暂停自动流程并输出报告，等待人工决策：

- **严重矛盾** — 同一主题 ≥2 张卡片结论相反，且无法按调和规则自动处理
- **知识库膨胀** — 单次策展新增卡片 >10 张，怀疑提取策略过于激进
- **模式失效** — 已有 pattern 被 ≥2 张新卡片推翻
- **画像冲突** — 用户画像中的偏好与近期卡片记录严重不一致

暂停时输出：问题描述 + 涉及的卡片/模式 ID + 建议的三种处理方式。

## 报告格式

```
═══ 策展报告 ═══
日期：YYYY-MM-DD
提取对话：N 条
新增经验卡片：K 张（列出标题）
更新已有卡片：M 张（列出标题和更新原因）
晋升为 pattern：P 条（列出标题）
修补 pattern：Q 条
矛盾调和：C 个（列出涉及的卡片）
── MEMORY 统计 ──
feedback: X 条（Y stale）
project: X 个（Y 路径失效）
reference: X 条
deprecated: X 条
```

## 权重机制（spec §7）

检索时 agenote_search 跨域扫描人类（weight 默认 1.5）+ agent（weight 默认 1.0）+ reconcile（weight 0.6-0.7）卡片，最终分数 = 原始相关度 × WEIGHT。

**curate 时的权重重分配公式**：

```
新 WEIGHT = 基础权重 × 使用系数 × 新鲜度系数

基础权重:   人类=1.5, agent=1.0, reconcile=0.6-0.7
使用系数:   1 + 0.1 × min(USAGE_COUNT, 10)   # 常用的提升，上限 +1.0
新鲜度系数: last_used 超 STALE_DAYS(30天) → 0.8，否则 1.0
```

**reconcile 权重梯度**：

- hermes / pi：0.7（自家或信任度高）
- opencode / crush / codex / claude：0.6（外部源，略低避免淹没 KB）

## 数据源

抽取器实现在 `ag_lib/extract/`，源列表与路径以代码为准（当前 7 源：opencode/crush/codex/claude/pi/hermes/zcode）。新增源参考任一现有 extractor 的签名 `() -> tuple[list[ReconciledFact], list[str]]`，在 `ag_lib/extract/__init__.py` 的 `_resolve_extractors()` 注册即可。

**三重只读保护**（所有 extractor 共享）：SQLite `mode=ro` + `PRAGMA query_only=1` + 仅 SELECT；JSONL 仅读；文件缺失返回 `([], [msg])` 不抛异常。

## 手动维护命令（MCP tool）

```
agenote_health()                          # KB 健康度
agenote_deduplicate()                     # 只检测重复
agenote_archive(stale=true)               # 只归档陈旧
agenote_archive(list_cards=true)          # 列出已归档
agenote_restore(target="<ID>")            # 恢复归档卡片
agenote_reindex()                         # 只重建索引
agenote_memory_search(stale=true)         # 陈旧记忆
agenote_extract(source="all", dry_run=True)    # 抽取原始对话为 Org 文件（不落盘）
agenote_extract(source="claude", date="2026-06-29", output_dir="/tmp/x")  # 指定日期 + 路径
```

## 跨 agent 工作流（5 个 MCP tool，默认 dry_run）

参考 MiMoCode Memory/Dream/Distill 体系。**纯只读/启发式，不调 LLM**，默认 `dry_run=True` 安全试跑：

```
# 1. 抽取：从各 AI 工具的原始对话 → Org 文件（~/Documents/Org/conversations/<date>/）
agenote_extract(source="all", dry_run=True)             # 全源 dry-run
agenote_extract(source="opencode", date="2026-06-29")  # 单源 + 指定日期
agenote_extract(source="all")                           # 实际写入磁盘

# 2. reconcile：把外部 agent memory 索引到 .reconcile/index.json（让 agenote_search 能搜到）
agenote_reconcile(source="hermes")                      # 单源
agenote_reconcile(source="all", dry_run=True)           # 全源 dry-run
agenote_reconcile(source="all")                         # 实际落盘

# 3. dream：从 reconcile 事实启发式提炼候选新卡片
agenote_dream(dry_run=True)

# 4. distill：把 KB 中反复使用的模式聚成 skill 草稿（写到 .distill/）
agenote_distill(dry_run=True)
```

### reconcile 行为细节

- **三重只读**：每个 extractor 内部 SQLite mode=ro + query_only + 仅 SELECT
- **KB 优先**：reconcile 抽到的事实若与 KB 已有卡片同名，跳过不索引
- **去重**：同一事实可能从多个 DB 出现（如 crush 全局 + bind-mount 项目级），按 `id` 去重保留先出现的
- **0-fact 警告**：extractor 跑通但抽不到任何事实（数据未生成 / schema 漂移）→ 自动报 `[warn]`
- **不写回源**：绝不写回任何外部 agent 的原始数据（DB/JSONL 只读）
- **不污染 KB**：reconcile 事实进 `.reconcile/index.json`（独立目录），不进 `experiences/`

### dream / distill 行为

- **dream**：找 reconcile 事实里高频出现、KB 未覆盖的主题 → 候选新卡片。**零候选即成功**。
- **distill**：把 KB 里 `type=ascended`/`usage_count≥2` 的卡片按 category+tech 聚类 → SKILL.md 草稿（写 `.distill/`，**不进 skills/**，人工 move 才生效）。**零候选即成功**。

## 健康度指标解读

| 指标           | 阈值              | 含义                                                                |
| -------------- | ----------------- | ------------------------------------------------------------------- |
| 孤立率         | <15% ✅ / <25% ⚠️ | 无 `[[file:]]` 链接的卡片占比                                       |
| 过时率         | <10% ✅ / <20% ⚠️ | stale 状态卡片占比                                                  |
| 类型偏斜       | <45% ✅           | 单一 type 占比过高                                                  |
| 薄弱类别       | ≥3 ✅             | 每个类别至少 3 张卡片                                               |
| by_source      | 各 agent 分布     | `by_source.counts`：每 agent 写卡数；`unknown` 列表暴露未登记 agent |
| 卡片增长率     | 月增 <20 张 ✅    | 超标的放慢提取频率                                                  |
| 矛盾未决数     | 0 ✅              | 必须处理，触发 Andon                                                |
| pattern 覆盖率 | ≥30% ✅           | 有对应 pattern 的经验占比                                           |

## 旧卡片审查清单

- 内容已过时 → 归档或标记过期
- 标题不包含结论 → 重命名
- 纯流水账 → 降级或删除
- 高度重复 → 合并保留更好的
- 与同类卡片矛盾 → 按调和规则处理
- 缺少时效性标注但涉及版本/API → 补充验证日期
- 无其他卡片/pattern 引用 → 评估补充关联或归档

## 何时不策展

- 单条经验刚写入 → 等 1 周积累 USAGE_COUNT 后再 curate
- 跨 agent 数据未跑通（schema 漂移）→ 先跑 `agenote_extract(source=<新源>, dry_run=True)` 验证 schema
- KB 总卡片 < 30 → curate 收益小，可手动维护

## 策展完成检查清单

- [ ] `agenote reindex` 已执行
- [ ] `agenote lint --fix` 无残留错误
- [ ] `agenote commit -m` 已执行（或确认无变更）
- [ ] 新增卡片元数据完整（category/tech/type/owner）
- [ ] 新增卡片含任务描述、执行过程、关键发现
- [ ] 代码块使用 Org mode 格式
- [ ] 仅提交本次策展涉及的文件

## 详细参考

- [策展工作流与质量标准](references/curation-guide.md) — 完整批处理步骤、矛盾调和、Andon 机制、报告格式
