# Agenote — 跨 Agent 经验平台

> 跨 Agent 知识管理与经验共享系统。通过 **MCP Server**（agent 编程入口）与 **CLI 命令**
> （终端调试与 cron 入口）双通道暴露统一 API；支持多个 AI agent 共享经验卡片、记忆、
> 策展与工作流蒸馏。

> **实现位置**：
>
> - CLI `~/.local/bin/agenote`（源码 `dotfiles/mutable/agenote/.local/bin/agenote`）
> - MCP server `~/.local/bin/agenote_mcp.py`（同上路径；长期进程，**改源码后必须 `pkill`
>   旧进程让客户端重连拉起新进程才能生效**）
> - 底层库 `ag_lib/`（`extract/`、`reconcile/` 等子包）
> - KB 仓库 `~/Documents/Org`（含 `agenote/` 卡片子目录、`conversations/` 抽取产物、`kb-viz.html`、`MEMORY.org`）

## 1. 系统架构

```
Agent Hermes ──┐
               ├── MCP Server ──┬── experiences/     (KB 卡片, ~/Documents/Org/agenote/)
Agent Pi ──────┤   (长期进程)   ├── memories/        (MEMORY.org)
               │                ├── .reconcile/      (跨 agent 事实索引，只读)
Agent Crush ───┘                ├── .distill/        (蒸馏草稿，未进 skills/)
                                ├── index.json       (全量索引)
                                └── ag_lib/          (CLI/MCP 共用底层库)
```

**核心组件**：

| 组件                 | 职责                                                    |
| -------------------- | ------------------------------------------------------- |
| `agenote` MCP Server | 对外 API 入口，agent 通过 MCP tool 调用                 |
| `agenote` CLI        | 终端入口：cron、调试、批处理；与 MCP 同一 `ag_lib` 底层 |
| `ag_lib/`            | 共享 Python 库（卡片模型、提取器、噪声过滤、git 包装）  |
| `experiences/`       | KB 卡片存储，按 `YYYYMMDD-HHMMSS.md` 命名               |
| `memories/`          | MEMORY.org 记忆文件，分 feedback/reference/project 三类 |
| `.reconcile/`        | 跨 agent 事实索引，只读抽取不回写                       |
| `.distill/`          | 工作流蒸馏草稿，人工 review 后才进 skills/              |
| `index.json`         | 全量索引，支持加权检索                                  |

**操作域**：

| `--domain` 值 | 含义                                   | 实际路径                   |
| ------------- | -------------------------------------- | -------------------------- |
| `agenote`     | agent 写入卡片域（CLI 默认；MCP 默认） | `~/Documents/Org/agenote/` |
| `human`       | 人类知识库根                           | `~/Documents/Org/`         |

> **特殊约束**：`reconcile` / `dream` / `distill` / `extract` **始终在 agenote 域**——这些命令
> 跨多源数据，不受 `--domain` 切换影响。

## 2. CLI 命令清单（29 个子命令）

CLI 是 agent 之外的人与 cron 入口，所有命令与 MCP 共用 `ag_lib` 底层，行为一致。
完整用法跑 `agenote --help`；`agenote help` 是 `help` 元命令（不算子命令）。

### 2.1 卡片 CRUD

| 子命令    | 功能                                                                        |
| --------- | --------------------------------------------------------------------------- |
| `add`     | 新建卡片（`--title` 必填；`--stdin` 读 body）                               |
| `get`     | 读取卡片（文件名或 ID）                                                     |
| `list`    | 列表（`--category` / `--type` / `--owner` / `--recent N` / `--all`）        |
| `update`  | 局部更新：`--status` / `--category` / `--append-to 章节 --append-text 内容` |
| `merge`   | 主+次卡片合并（合并多次卡片为一张）                                         |
| `connect` | 在两张卡片间建双向链接（`--desc 描述`）                                     |
| `delete`* | （CLI 未导出；MCP `agenote_archive` 是规范删除路径）                        |

### 2.2 检索与发现

| 子命令   | 功能                                                       |
| -------- | ---------------------------------------------------------- |
| `search` | 全文检索（关键词默认按空格/斜杠/逗号拆；`--regex` 切正则） |
| `tags`   | 按标签精确检索                                             |
| `fields` | 列出已有 `category`/`tech`/`type`/`owner` 值（防止造词）   |
| `inbox`  | 快速捕获到 `inbox.org`（`agenote inbox "想法"`）           |

### 2.3 记忆系统

`agenote memory` 子命令树（与 MCP `agenote_memory_*` 对齐）：

```bash
agenote memory                           # 列表概览
agenote memory --type feedback           # 按类型过滤
agenote memory --project <name|path|.>   # 按项目检索
agenote memory --stale                   # 列出陈旧记忆
agenote memory --add --type X --title Y --stdin   # 新增
agenote memory --touch <ID>              # 更新时间戳
agenote memory --archive <ID>            # 归档到 deprecated
agenote memory --archive-to-file <ID>    # feedback → MEMORY-ARCHIVE.org
agenote memory --stale --auto-archive-days 60   # 自动归档陈旧 feedback
agenote memory --project-touch <name>    # 更新项目 LAST_ACTIVE
agenote memory --project <name> --auto-update    # 自动更新元数据
agenote memory --get                     # 全文输出
```

### 2.4 健康度与策展

| 子命令        | 功能                                                         |
| ------------- | ------------------------------------------------------------ |
| `lint`        | 格式+语义校验（`--fix` 只修可安全自动化的；`--check` 退出码=问题数） |
| `format`      | 格式化卡片（默认直接写盘；`--check` 只检查）                 |
| `review`      | 单卡片审查（`--fix` 自动改）                                 |
| `deduplicate` | 重复检测（`--threshold 0.7`，默认 Jaccard 相似度阈值）       |
| `archive`     | 归档（指定 ID / `--stale` 自动归档陈旧 / `--list` 列已归档） |
| `restore`     | 恢复已归档卡片（`--status stable`）                          |
| `gaps`        | 知识空白检测（按 category×type 矩阵，`--stale-days 90`）     |
| `health`      | 健康度报告（`--duplicates` / `--quality` 开关）              |
| `curate`      | **一键策展**：健康检查+权重重分配+去重+归档+重建索引         |
| `reindex`     | 仅重建 `index.json`（不跑策展其余步骤）                      |
| `stats`       | 统计概览（总数/按维度分布/MEMORY 统计）                      |

### 2.5 跨 agent 与会话抽取

| 子命令      | 功能                                                                   |
| ----------- | ---------------------------------------------------------------------- |
| `reconcile` | 只读抽取其他 agent 事实到 `.reconcile/`（`--source hermes/pi/...`）    |
| `dream`     | 启发式提炼候选新卡片（不调 LLM，零候选合法）                           |
| `distill`   | 工作流蒸馏：把反复使用经验打包成 SKILL.md 草稿，写 `.distill/`         |
| `extract`   | 跨 agent 原始对话抽取为 Org 文件（**输出到 `conversations/<date>/`**） |

### 2.6 系统维护

| 子命令   | 功能                                                                 |
| -------- | -------------------------------------------------------------------- |
| `init`   | 初始化目录结构 + git 仓库 + 初始 commit（`--no-git` 跳过 git）       |
| `commit` | **策展产物 git 提交**（见 §5.5）：精准 add + commit message 模板对齐 |
| `touch`  | 更新卡片时间戳（`--used-only` 只更新 `LAST_USED`）                   |
| `help`   | 显示 `agenote --help` 完整用法                                       |

## 3. MCP 工具清单

> MCP 是 agent 在线会话的标准入口。**改源码后必须 `pkill -f agenote_mcp.py`** 让客户端
> 重连拉起新进程，否则加载的是旧字节码。

### 3.1 卡片操作

| 工具                  | 功能                                           |
| --------------------- | ---------------------------------------------- |
| `agenote_add`         | 创建新卡片                                     |
| `agenote_get`         | 读取单张卡片（可选递增 USAGE_COUNT）           |
| `agenote_list`        | 按 category/type/owner 过滤列表                |
| `agenote_search`      | 跨域加权检索（人类卡片 1.5x，agent 卡片 1.0x） |
| `agenote_touch`       | 更新时间戳，递增 USAGE_COUNT                   |
| `agenote_update`      | 局部更新已有卡片字段/章节                      |
| `agenote_merge`       | 主+次卡片合并                                  |
| `agenote_connect`     | 在两张卡片间建双向链接                         |
| `agenote_archive`     | 归档（指定/自动归陈旧/列已归档）               |
| `agenote_restore`     | 恢复已归档卡片                                 |
| `agenote_deduplicate` | 重复检测（标题相似度 + category/tech 匹配）    |
| `agenote_review`      | 单卡片审查（`fix=True` 自动修复）              |

### 3.2 记忆操作

| 工具                      | 功能                                   |
| ------------------------- | -------------------------------------- |
| `agenote_memory_add`      | 添加记忆（feedback/reference/project） |
| `agenote_memory_get`      | 读取 MEMORY.org 全文或分节             |
| `agenote_memory_overview` | 概览统计或按类型列出标题               |
| `agenote_memory_search`   | 按项目检索或列出陈旧记忆               |

### 3.3 系统维护

| 工具              | 功能                                                                  |
| ----------------- | --------------------------------------------------------------------- |
| `agenote_curate`  | 一键策展（健康+权重+去重+归档+重建索引）                              |
| `agenote_lint`    | 格式+语义校验（`fix=True` 只修可安全自动化的格式问题；语义问题只报告） |
| `agenote_health`  | 健康度报告（孤立率/过时率/类型偏斜/薄弱类别）                         |
| `agenote_stats`   | 统计概览                                                              |
| `agenote_gaps`    | 知识空白检测（category×type 矩阵）                                    |
| `agenote_reindex` | 全量扫描重建 index.json                                               |
| `agenote_init`    | 初始化目录结构 + 模板文件                                             |
| `agenote_commit`  | **KB 策展产物 git 提交**（默认 `dry_run=True` 预览；2026-07-07 新增） |

### 3.4 跨 Agent 协同

| 工具                | 功能                                                                               |
| ------------------- | ---------------------------------------------------------------------------------- |
| `agenote_reconcile` | 跨 agent memory 只读 reconcile                                                     |
| `agenote_dream`     | memory consolidation：高频事实启发式提炼候选卡片                                   |
| `agenote_distill`   | 工作流蒸馏：重复经验打包成 skill 草稿                                              |
| `agenote_extract`   | **跨 agent 原始对话抽取为 Org 文件**（默认 `dry_run=False` 落盘；2026-07-07 修复） |

## 4. CLI ↔ MCP 对照表

每个 CLI 子命令都对应一个 MCP tool（或一组）。**默认安全姿态对比**：

| 维度     | CLI                               | MCP                                  |
| -------- | --------------------------------- | ------------------------------------ |
| 默认值   | **直接执行**（人类手动确认）      | **`dry_run=True`**（agent 两次确认） |
| 输出     | 文本（人友好）                    | JSON（agent 解析友好）               |
| 启动开销 | 每次解释器+argparse（~50ms）      | 长连接复用                           |
| 适合场景 | cron / 调试 / 批处理 / 一次性任务 | agent 会话内在线调用                 |
| 进程模型 | 单次 fork+exit                    | 长进程（**改源码后需 pkill 重连**）  |

**安全默认值差异（关键）**：

| 命令        | CLI 默认         | MCP 默认        | 含义                                                                        |
| ----------- | ---------------- | --------------- | --------------------------------------------------------------------------- |
| `commit`    | **直接 commit**  | `dry_run=True`  | CLI 给 `dry_run` flag 后才预览；MCP 默认预览，必须 `dry_run=False` 才真提交 |
| `extract`   | `--dry-run` 标志 | `dry_run=False` | **2026-07-07 修复**：MCP 翻为 `False`，CLI 仍需显式 `--dry-run`             |
| `reconcile` | `--dry-run` 标志 | `dry_run=True`  | 均为默认预览，需显式 flag 才落盘                                            |
| `dream`     | `--dry-run` 标志 | `dry_run=True`  | 启发式纯函数式安全                                                          |
| `distill`   | `--dry-run` 标志 | `dry_run=True`  | 草稿落 `.distill/`，但 review 才能进 skills/                                |
| `curate`    | 直接执行         | 直接执行        | 重排 + 归档 — 自动跑；CLI 跑完建议 `agenote commit`                         |
| `archive`   | 直接归档         | 直接归档        | 改 STATUS 即可，文件保留                                                    |

## 5. 卡片格式与策展

### 5.1 卡片格式

```markdown
#+TITLE: 卡片标题
#+ENTRY_TYPE: note|mistake|ascended
#+CATEGORY: guix|emacs|hermes|...
#+TECH: guix|emacs|hermes|...
#+TYPE: debug|refactor|research|workflow|feature|config
#+OWNER: human|ai|collab
#+CREATED: <timestamp>
#+LAST_VERIFIED: <timestamp>
#+LAST_USED: <timestamp>
#+USAGE_COUNT: 0
#+STATUS: stable|stale|deprecated
#+SUMMARY: 一句话总结

正文内容...
```

**字段说明**：

| 字段         | 说明                                                                    |
| ------------ | ----------------------------------------------------------------------- |
| `ENTRY_TYPE` | `note`（经验笔记）、`mistake`（踩坑记录）、`ascended`（已提炼为工作流） |
| `TYPE`       | `config, debug, feature, refactor, research, workflow`                  |
| `OWNER`      | `human, ai, collab`                                                     |
| `STATUS`     | `stable`（活跃）、`stale`（>90 天未验证）、`deprecated`（已归档）       |

**合法值是 CLI 强校验的**：

```
VALID_TYPES   = (config, debug, feature, refactor, research, workflow)
VALID_OWNERS  = (ai, collab, human)
STALE_DAYS    = 30    # memory 陈旧阈值（KB 卡片阈值默认 90 天）
```

### 5.2 权重与策展流程

| 来源                    | 权重   |
| ----------------------- | ------ |
| 人类卡片（owner=human） | 1.5x   |
| Agent 卡片（owner=ai）  | 1.0x   |
| Reconcile 事实          | < 1.0x |

`agenote_curate`（一键策展，CLI 与 MCP 均直接执行）：

```
1. 健康检查 → 孤立率/过时率/类型偏斜
2. 权重重分配 → 基于 USAGE_COUNT + LAST_USED
3. 去重检测 → 标题相似度 ≥ 0.7
4. 归档陈旧 → STATUS=stale 且 LAST_VERIFIED > 90 天
5. 重建索引 → index.json 全量重写
```

### 5.3 健康度指标

| 指标     | 阈值  | 说明                   |
| -------- | ----- | ---------------------- |
| 孤立率   | < 15% | 无引用的卡片比例       |
| 过时率   | < 10% | STATUS=stale 的比例    |
| 类型偏斜 | < 45% | 单一 TYPE 的占比       |
| 薄弱类别 | ≤ 3   | 卡片数 < 3 的 category |

### 5.4 跨 Agent 机制

| 流程        | 模式                       | 关键约束                                                  |
| ----------- | -------------------------- | --------------------------------------------------------- |
| Reconcile   | 只读 → `.reconcile/`       | 绝不写回源 agent；幂等；KB 优先于 reconcile 事实          |
| Dream       | 启发式（不调 LLM）         | 默认 `dry_run`；先做噪声过滤（见 §6 D5）                  |
| Distill     | 写 `.distill/`             | 草稿不直接进 `skills/`；人工 review 后才生效              |
| **Extract** | 写 `conversations/<date>/` | `date` 非空时按对话时间戳过滤；`limit 0=不限` 见 §6 D3/D4 |

### 5.5 Git 提交收尾（`agenote commit`）

> **设计原则**：KB 仓库（`~/Documents/Org`）是 git 跟踪的，策展产物（`experiences/*.md` +
> `index.json` + `conversations/<date>/` + `kb-viz.html`）必须有针对性的入库。`git add -A`
> 会把同仓库里别的修改（如临时文件）一起吞，必须避免。

CLI `agenote commit -m "..."` 默认行为（**2026-07-07 D1 修复后**）：

```bash
agenote commit -m "策展: (agenote) 新增 K 张 / 更新 M 张"
agenote commit --all -m "..."              # 退回 git add -A 语义（请谨慎）
agenote commit --no-gpg-sign -m "..."      # 显式跳过 GPG（cron 等无 pinentry 场景）
```

- **精准 add 范围**：`agenote/experiences/`、`agenote/experiences/index.json`、
  `conversations/<date>/`、`kb-viz.html` 等策展产物
- **git 根解析**：用 `git rev-parse --show-toplevel` 找真实工作树（**不**假设
  `~/Documents/Org/agenote/` 下有 `.git`）
- **GPG 签名**：遵循 `commit.gpgsign=true`，`--no-gpg-sign` 显式 flag 才跳过
- **message 前缀**：默认 `策展:`，对齐 `~/.config/git/gitmessage` 模板

MCP `agenote_commit` 默认行为（**2026-07-07 D1 新增**）：

- `dry_run=True`（**预览**：返回 `add_targets` / `staged_files` 清单）
- 显式 `dry_run=False` 才真提交

## 6. 已落地修复（2026-07-07）

> 任务书：`agenote-defects-2026-07-07.md`（独立于 KB 的交付文档）。本节是按修复点的**功能说明**
> 视角摘抄（详细的端到端验证见任务书 §3）。

| ID  | 主题                     | CLI 行为变化                                                     | MCP 行为变化                                                 | status    |
| --- | ------------------------ | ---------------------------------------------------------------- | ------------------------------------------------------------ | --------- |
| D1  | `commit` 子命令重构      | 精准 add + 解析真实 git 根 + 遵循 GPG；新增 `--all` 退回旧行为   | 新增 `agenote_commit` tool，默认 `dry_run=True` 预览         | ✅ 已修复 |
| D2  | `extract` MCP 默认不落盘 | `agenote extract --dry-run` 仍需显式传                           | **默认 `dry_run=False`**（之前 `True`）；不传 dry_run 即落盘 | ✅ 已修复 |
| D3  | `extract` 按天增量       | `--date YYYY-MM-DD` 真正按对话时间戳过滤（之前仅决定输出目录名） | 同上（同步修复）                                             | ✅ 已修复 |
| D4  | `extract` 上限参数化     | `--limit 0` 不限；`--limit N` 截断并提示                         | `limit` 参数暴露（MCP）/0=不限                               | ✅ 已修复 |
| D5  | `dream` 噪声候选         | 仍 `dry_run`，但聚类前过滤 `[CONTEXT]`/`[GOAL]` 等噪声标记       | 同上                                                         | ✅ 已修复 |

**已加入 `ag_lib/core.py:NOISE_MARKERS`**（D5）：

```python
NOISE_MARKERS = [
    "[CONTEXT]", "[GOAL]", "[DOWNSTREAM]", "[REQUEST]",
    "[SYSTEM NOTIFICATION]",
    # oh-my-pi prompt 模板标记 + harness 通知
]
```

效果（defects 端到端验证）：`agenote dream` 候选 `representative_title` 不再是
`"[CONTEXT]"`，改为真实标题（如 `"我想要重新设计 pi agent"`）。

**`ReconciledFact` 时间戳字段**（D3）：

6 个 extractor（opencode / zcode / crush / codex / claude / pi）已填充
`ReconciledFact.timestamp`；hermes 无时间戳源退化为**全量不静默丢**（不假装按日期过滤）。

## 7. 设计原则

1. **只读 reconcile**：跨 agent 协同只抽取事实，绝不回写源文件
2. **人工 gate**：distill 产出的 skill 草稿必须人工 review 才生效
3. **权重分层**：人类经验 > agent 经验 > reconcile 事实
4. **幂等操作**：curate/reindex/reconcile/extract-with-same-date 可安全重复执行
5. **零候选合法**：dream/distill 返回空不视为错误
6. **双通道一致**：CLI 与 MCP 共用 `ag_lib`，行为终态对齐；仅在"默认是否安全"上分态度
   —— **CLI 默认执行（人类手动控制）vs. MCP 默认预览（agent 需要二次确认）**

## 8. 关键约束

| 约束             | 说明                                                          |
| ---------------- | ------------------------------------------------------------- |
| 文件命名         | 卡片文件名格式 `YYYYMMDD-HHMMSS.md`，不允许中文/空格          |
| `index.json`     | 单一权威索引，禁止手动编辑                                    |
| `skills/` 目录   | distill 草稿不直接写入，必须经人工移动                        |
| `reconcile`      | 不回写源 agent 的 memory store                                |
| 归档             | 只改 STATUS 字段，不删除文件                                  |
| MCP 进程         | 改源码后 `pkill -f agenote_mcp.py` 让客户端重连               |
| KB 域 `--domain` | `reconcile`/`dream`/`distill`/`extract` **始终在 agenote 域** |
| `commit` 取证    | 不**无脑 `git add -A`**；精准 add 策展产物                    |
| `extract` 取证   | 不使用**硬截断**的 limit（除非显式 `--limit`）                |
| `dream` 取证     | 不使用**未过滤噪声**的事实聚类                                |

## 9. 配置常量（`~/.local/bin/agenote` 头部）

| 常量            | 值                                                       | 说明                          |
| --------------- | -------------------------------------------------------- | ----------------------------- |
| `KB_ROOT`       | `/home/brokenshine/Documents/Org`                        | 人类知识库根（含 `agenote/`） |
| `STALE_DAYS`    | `30`                                                     | memory 陈旧阈值               |
| `VALID_TYPES`   | `(config, debug, feature, refactor, research, workflow)` | —                             |
| `VALID_OWNERS`  | `(ai, collab, human)`                                    | —                             |
| 默认 `--domain` | `agenote`                                                | agent 写入域（卡片子目录）    |

---

## 修订记录

- **2026-07-07**：补全 CLI 子命令（27 个）、CLI↔MCP 对照表、D1-D5 修复说明、`commit` 收尾设计原则、`NOISE_MARKERS` 与 `ReconciledFact.timestamp` 字段说明。
