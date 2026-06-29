# 跨 Agent 经验平台（Cross-Agent Curator）

> 覆盖本机所有 agent 的统一经验策展基础设施。基于 MiMoCode（opencode fork）的
> Memory + Dream + Distill 体系，补全本机 `kb` + `agenote` 现有能力的缺口。
>
> **历史规划**见 [`PLAN.md`](../../PLAN.md)（草案存档）。
> **本文档记录当前已实现 + 待实施 + 设计原则 + 调用示例**。

| 字段 | 值 |
|---|---|
| 适用范围 | 本机所有 agent（pi / hermes / OMP / crush / opencode / MiMoCode / claude-code）及其持久化记忆层 |
| 已实现 | 第一部分 Phase 1-5（2026-06-29 实测通过） |
| 待实施 | 第二部分 Phase 6-11（atelier 子系统升级，依赖未具备的运行时） |
| 核心交付物 | `agenote-mcp` 增强版（17→20 tool）+ 3 个手动触发工作流 + 2 份 SKILL 文档 |

---

## 1. 总体目标

1. **一个 MCP server，所有 agent 都能用** —— `agenote-mcp` 是 interface 入口；
   写入时自动打 `source_agent` 标签，跨 agent 检索时知道这卡片谁写的。
2. **三个手动工作流**（**非 cron**，本机无 mcron 落点）：
   - `reconcile` 把其他 agent 的 memory **只读** 拉进检索范围
   - `dream` 从 reconcile 事实启发式提炼**候选**新卡片
   - `distill` 把 KB 里重复工作流聚成 **skill 草稿**（不直接进 skills/）
3. **KB 优先**：`~/Documents/Org/agenote/` 是唯一权威 KB；其他 agent memory
   走只读索引，**绝不写回源**、**绝不污染权威 KB**。

---

## 2. 已实现（Phase 1-5）

### Phase 1 — `source_agent` 标签体系（来源溯源）

**问题**：原 `agenote_add` 写入的卡片不带来源标记，无法分辨"pi 写的"还是"hermes 写的"。

**改动**：
- `kb_lib/core.py`：新增 `KBContext.agent_name` 字段、`KNOWN_AGENTS` 白名单、`default_agent()` 函数（读 `AGENOTE_AGENT` 环境变量，回退 `"pi"`）。
- `kb_lib/cards.py`：`cmd_add` 写入 `:SOURCE_AGENT: <name>` org 属性（白名单外只警告不阻塞）。
- `kb_lib/_card_dict`：解析 `:SOURCE_AGENT:` 进入 index。
- `stow/pi/.config/pi/mcp.json`：agenote MCP server 启动时注入 `AGENOTE_AGENT=pi` env。

**数据迁移**：现有 5 张卡片补 `SOURCE_AGENT: pi`（按"原 owner 为 ai + 来自 pi-hooks 写入"判定），幂等（已存在则跳过）。

**验证**：
```bash
AGENOTE_AGENT=hermes python3 -c "
import sys; sys.path.insert(0, '/home/brokenshine/Projects/Config/Guix-configs/stow/emacs/.local/bin')
import kb_lib.core as core
print(core.agenote_context().agent_name)  # 'hermes'
"
# 无 env → 'pi'
```

### Phase 2 — 跨 agent memory reconcile（只读索引）

**问题**：其他 agent 的 memory（hermes holographic DB 等）是平行孤岛，经验无法跨 agent 流动。

**改动**：
- `kb_lib/reconcile.py`（新增）：hermes extractor，**三重只读保护**：
  1. SQLite `file:...mode=ro` URI
  2. `PRAGMA query_only = 1`（连接级写锁）
  3. 只 SELECT，从不构造写语句
- `agenote_mcp.py` `_cross_domain_search`：把 reconcile 索引作为额外搜索目标（`domain="reconcile"`，`source="hermes"`）。
- `agenote_reconcile(source, dry_run)` MCP tool。

**hermes schema 实际为**（勘误 PLAN.md：原文写的 `entry_type` 字段、`memory_fts` 表均不存在）：
```
facts(fact_id, content, category, tags, trust_score, retrieval_count, helpful_count, hrr_vector)
facts_fts(content, tags)  -- FTS5
entities / fact_entities / memory_banks (HRR dim=1024)
```
映射策略：`category` → kb `category`；`trust_score` → 影响 `weight`（0.5 → 0.7，封顶 1.0 避免淹没 KB 卡片）；`content` 提【】括号标题。

**只读安全性验证**：
```bash
md5sum ~/.local/share/hermes/memory_store.db  # 前后哈希一致
```

**当前支持的 source**：`KNOWN_SOURCES = {"hermes": extract_hermes}`。claude-code / crush / opencode / mimocode 的 memory 实测路径不存在（`~/.claude/projects` 等缺失），未登记；待对应 agent memory 落地后加 extractor。

### Phase 3 — dream（启发式 memory consolidation）

**问题**：reconcile 拉来的事实 KB 没收录的主题该被补充进来。

**改动**：
- `kb_lib/dream.py`（新增）：启发式算法（**不调 LLM**，避免烧 token）：
  - 对 reconcile 事实 token 化（中文 2-gram + ASCII 词）
  - 停用词过滤（中文虚词 + 英文 the/a 等）
  - 词频 ≥ 2 + KB 未覆盖 → 候选
  - Top-5 候选返回
- `agenote_dream(window_days, dry_run=True)` MCP tool，**默认 dry_run**。

**关键原则**：
- **零候选即成功**：reconcile 事实全部被 KB 覆盖 → 返回"无候选"，不凑数
- **archive 被取代的旧卡片**：合并新候选时若发现 KB 有同主题低质量卡片，自动归档
- **source_agent = "pi-dream"**：dream 生成的卡片打这个标签，便于溯源

### Phase 4 — distill（workflow packaging）

**问题**：KB 里反复使用的同一工作流模式应该被沉淀为 skill。

**改动**：
- `kb_lib/distill.py`（新增）：
  - 入选条件：`type=ascended`（多轮试错验证）**或** `usage_count >= 2`（反复使用）
  - 聚类键：`(category, tech)`，同主题 ≥ 2 张才成候选
  - 草稿写到 `~/Documents/Org/agenote/.distill/<日期>-<name>-draft.md`，**不直接进 skills/**
  - SKILL.md 模板填空（name/description/触发场景/源卡片列表），正文留空人工填
- `agenote_distill(window_days, dry_run=True)` MCP tool，**默认 dry_run**。

**关键原则**：
- **零候选即成功**：KB 无重复工作流 → 返回"无候选"，不凑数（抄 MiMoCode distill.txt:39-41）
- **草稿不进 skills/**：避免污染 agent 的 skill 列表，人工 `move` 到 `~/.config/agents/skills/<name>/SKILL.md` 才生效
- **幂等**：已存在的同主题 draft 跳过，不重复生成

### Phase 5 — `agenote_health` 跨 agent 维度

**问题**：健康度报告缺少"哪个 agent 贡献了多少"的视角。

**改动**：`agenote_health` 返回新增 `by_source` 字段：
```json
{
  "counts": {"pi": 5, "hermes": 0},
  "known_agents": ["claude-code", "crush", "hermes", "mimocode", "omp", "opencode", "pi", "pi-distill", "pi-dream"],
  "unknown": []
}
```
`unknown` 列表暴露未登记 agent 名（agent_name 在白名单外但被记录），便于发现新 agent。

---

## 3. 调用示例

### agent 写入一张带 source_agent 的卡片

```python
# pi 环境（默认）：mcp.json 已注入 AGENOTE_AGENT=pi
agenote_add(title="...", entry="note", body="...")

# hermes 环境（若将来 mcp 注册了外部 server）：设置 env=hermes 后调用
# 卡片 org 属性：:SOURCE_AGENT: hermes
# index.json 含 source_agent="hermes"
```

### 跨 agent 搜索（搜索结果同时含 KB 卡片 + reconcile 事实）

```python
hits = agenote_search(query="emacs 行号")
# [
#   {"domain": "reconcile", "source": "hermes", "title": "Emacs 中收窄行号列与正文之间间距..."},
#   {"domain": "agenote", "weight": 1.0, "title": "pi-extension ..卡..."},
#   ...
# ]
```

### 周期策展（手动）

```python
# 1. 拉取 hermes 新事实（默认非 dry_run，直接落盘 .reconcile/index.json）
agenote_reconcile(source="hermes")

# 2. dream 候选新卡片（默认 dry_run，review 后 dry_run=False 才写）
agenote_dream(dry_run=True)        # 看候选
# 检查候选 → agenote_dream(dry_run=False)  # 确认写入

# 3. distill skill 草稿（默认 dry_run，review 后 dry_run=False 才写）
agenote_distill(dry_run=True)      # 看候选聚类
# 检查候选 → agenote_distill(dry_run=False)  # 写入 .distill/
```

### 查看健康度

```python
h = agenote_health()
print(h["by_source"])      # 各 agent 写卡分布
print(h["unknown"])        # 未登记 agent 名列表
```

---

## 4. 设计原则（从 MiMoCode 提炼，已落代码）

| 原则 | 落点 |
|---|---|
| **Memory is a curated notebook, history is a firehose** | `agenote_search` 先走 KB + reconcile 索引，再走原始轨迹。 |
| **No extract without evidence** | `dream`/`distill` 词频 ≥ 2 + 聚类 ≥ 2 才升级；零候选即合法。 |
| **Verbatim > paraphrase** | `reconcile.py` 写出的事实 `content` **逐字保留**（标题才提取【】）。 |
| **Authoritative hit, escalate progressively** | KB 优先于 reconcile；同名标题冲突 → reconcile 跳过（KB 优先）。 |
| **Section budgets** | (待 Phase 5 扩展为 MEMORY.org budget 检查，本轮未做) |

---

## 5. 关键约束（不要破坏）

1. **只读 reconcile**：hermes DB 三重只读保护，md5sum 前后必须一致（验证脚本见 §6）。
2. **KB 优先**：reconcile 抽到的事实若与 KB 卡片同名 → 跳过（`reconcile.py:_kb_titles()`）。
3. **默认 dry_run**：dream / distill / reconcile 默认 `dry_run=True`，必须显式 `dry_run=False` 才写。
4. **白名单非阻塞**：未知 agent_name 只警告不 raise，便于新增 agent 而无需改代码。
5. **stow 包改源即生效**：`~/.local/bin/kb_lib/` 是 stow 软链 → 源，**不需 `blue home`**（仅 dotfiles/enable/ 才需要）。

---

## 6. 验证脚本

完整端到端冒烟测试（host-spawn）：

```bash
host-spawn bash -c '
cd ~/Projects/Config/Guix-configs/stow/emacs/.local/bin
AGENOTE_AGENT=pi ~/.guix-home/profile/bin/python3 << "PYEOF"
import sys, json; sys.path.insert(0, ".")
import agenote_mcp as m

# 1. health 含 by_source
h = m.agenote_health()
assert "by_source" in h

# 2. reconcile 索引 hermes
r = m.agenote_reconcile(source="hermes", dry_run=True)
assert r["errors"] == 0
assert r["indexed"] >= 0

# 3. dream/distill 返回合法结构（零候选亦 OK）
d = m.agenote_dream(dry_run=True)
assert "candidates" in d
di = m.agenote_distill(dry_run=True)
assert "candidates" in di

# 4. search 能命中 reconcile 事实
hits = m.agenote_search(query="hermes", limit=5)
reconcile_hits = [h for h in hits if h.get("domain") == "reconcile"]
print(f"OK: {len(reconcile_hits)} reconcile hits among {len(hits)} total")
PYEOF
'
```

---

## 7. 待实施：atelier 升级（Phase 6-11）

**状态**：仅留 spec，**未实施**。原因实测两个硬约束：

1. **atelier 全程 `node:fs`（status.json 文件），无任何 SQLite**。Phase 6 引入
   SQLite Registry 是**新增运行时依赖**，pi 运行时 `bun` 不可用、`node:sqlite`
   需 Node 22+ flag，无法确认可加载。
2. **`pi`/`bun` 不在 host PATH**（pi 是 npm 包，入口二进制不同）→ 无法
   typecheck/跑/验证任何 atelier `.ts`。

按"未验证就不宣称完成"原则，本轮不盲写代码。完整 spec 见
[`PLAN.md` 第二部分 §12-23](../../PLAN.md)，包含：
- Phase 6: Atelier Registry (SQLite 全局索引)
- Phase 7: Return Header 协议（强制 `**Status**: success/partial/failed/blocked`）
- Phase 8: Completion Gate（task list 真相优先于 self-report）
- Phase 9: System-spawned Agent 分类（`SYSTEM_SPAWNED_AGENT_TYPES` 白名单）
- Phase 10: 长程任务 Checkpoint + Resume
- Phase 11: Workflow 层抽象（DAG + depends_on）

实施前置条件（待补）：
- 决定 SQLite 引入方式（`bun:sqlite` / `node:sqlite` flag / 复用现存 sqlite3）
- 在 pi 运行环境里执行（容器内无验证能力）
- 先做 Phase 7（纯字符串解析，最低风险）+ Phase 9（常量定义），再做依赖 SQLite 的 Phase 6/8/10/11