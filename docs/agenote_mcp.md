# Agenote — 跨 Agent 经验平台

> 跨 Agent 知识管理与经验共享系统。通过 MCP Server 暴露统一 API，支持多个 AI agent 共享经验卡片、记忆、策展与工作流蒸馏。

## 1. 系统架构

```
Agent Hermes ──┐
               ├── MCP Server ──┬── experiences/    (KB 卡片)
Agent Pi ──────┤                ├── memories/       (MEMORY.org)
               │                ├── .reconcile/     (跨 agent 事实索引)
Agent Crush ───┘                ├── .distill/       (蒸馏草稿)
                                └── index.json      (全量索引)
```

**核心组件**：

| 组件                 | 职责                                                    |
| -------------------- | ------------------------------------------------------- |
| `agenote` MCP Server | 对外 API 入口，所有读写操作经此路由                     |
| `experiences/`       | KB 卡片存储，按 `YYYYMMDD-HHMMSS.md` 命名               |
| `memories/`          | MEMORY.org 记忆文件，分 feedback/reference/project 三类 |
| `.reconcile/`        | 跨 agent 事实索引，只读抽取不回写                       |
| `.distill/`          | 工作流蒸馏草稿，人工 review 后才进 skills/              |
| `index.json`         | 全量索引，支持加权检索                                  |

## 2. 工具清单

### 2.1 卡片操作

| 工具                  | 功能                                           |
| --------------------- | ---------------------------------------------- |
| `agenote_add`         | 创建新卡片                                     |
| `agenote_get`         | 读取单张卡片（可选递增 USAGE_COUNT）           |
| `agenote_list`        | 按 category/type/owner 过滤列表                |
| `agenote_search`      | 跨域加权检索（人类卡片 1.5x，agent 卡片 1.0x） |
| `agenote_touch`       | 更新时间戳，递增 USAGE_COUNT                   |
| `agenote_archive`     | 归档（指定/自动归陈旧/列已归档）               |
| `agenote_restore`     | 恢复已归档卡片                                 |
| `agenote_deduplicate` | 重复检测（标题相似度 + category/tech 匹配）    |

### 2.2 记忆操作

| 工具                      | 功能                                   |
| ------------------------- | -------------------------------------- |
| `agenote_memory_add`      | 添加记忆（feedback/reference/project） |
| `agenote_memory_get`      | 读取 MEMORY.org 全文或分节             |
| `agenote_memory_overview` | 概览统计或按类型列出标题               |
| `agenote_memory_search`   | 按项目检索或列出陈旧记忆               |

### 2.3 系统维护

| 工具              | 功能                                                         |
| ----------------- | ------------------------------------------------------------ |
| `agenote_curate`  | 一键策展：健康检查 + 权重重分配 + 去重 + 归档陈旧 + 重建索引 |
| `agenote_health`  | 输出健康度报告（孤立率/过时率/类型偏斜/薄弱类别）            |
| `agenote_stats`   | 统计概览（总数/按维度分布/MEMORY 统计）                      |
| `agenote_reindex` | 全量扫描重建 index.json                                      |
| `agenote_init`    | 初始化目录结构 + 模板文件                                    |

### 2.4 跨 Agent 协同

| 工具                | 功能                                                 |
| ------------------- | ---------------------------------------------------- |
| `agenote_reconcile` | 跨 agent memory 只读 reconcile（只读抽取，不回写源） |
| `agenote_dream`     | memory consolidation：高频事实启发式提炼候选卡片     |
| `agenote_distill`   | 工作流蒸馏：重复经验打包成 skill 草稿                |

## 3. 卡片格式

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
| `TYPE`       | 决定卡片在策展中的权重分配                                              |
| `OWNER`      | 标记创建者，影响检索权重（human 1.5x，ai 1.0x）                         |
| `STATUS`     | `stable`（活跃）、`stale`（>90 天未验证）、`deprecated`（已归档）       |

## 4. 跨 Agent 机制

### 4.1 Reconcile（事实抽取）

从其他 agent 的 memory store 只读抽取事实，写入 `.reconcile/index.json`：

- **只读**：不写回源文件，不污染权威 KB
- **权重低于 KB 卡片**：检索时 KB 卡片优先
- **幂等**：重复 reconcile 不产生重复条目

```python
# 典型调用
agenote_reconcile(source="hermes", dry_run=True)   # 预览
agenote_reconcile(source="hermes", dry_run=False)  # 落盘
```

### 4.2 Dream（经验启发）

从 reconcile 事实中，按关键词频次提炼候选卡片：

- **纯启发式**：不调 LLM，可安全手动触发
- **默认 dry_run**：只返回候选清单
- **零候选合法**：KB 已覆盖所有高频主题时返回空

### 4.3 Distill（工作流蒸馏）

扫描 KB 中被反复使用的卡片（type=ascended 或 usage_count≥2）：

- **聚类**：按 category+tech 分组，同主题 ≥2 张才生成草稿
- **草稿位置**：`.distill/SKILL.md`，不直接进 skills/ 目录
- **人工 review**：移动到 skills/ 后才生效
- **零候选合法**：无重复工作流时返回空

## 5. 权重与策展

### 5.1 检索权重

| 来源                    | 权重   |
| ----------------------- | ------ |
| 人类卡片（owner=human） | 1.5x   |
| Agent 卡片（owner=ai）  | 1.0x   |
| Reconcile 事实          | < 1.0x |

### 5.2 策展流程（agenote_curate）

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

## 6. 设计原则

1. **只读 reconcile**：跨 agent 协同只抽取事实，绝不回写源文件
2. **人工 gate**：distill 产出的 skill 草稿必须人工 review 才生效
3. **权重分层**：人类经验 > agent 经验 > reconcile 事实
4. **幂等操作**：curate/reindex/reconcile 可安全重复执行
5. **零候选合法**：dream/distill 返回空不视为错误

## 7. 关键约束

| 约束         | 说明                                                 |
| ------------ | ---------------------------------------------------- |
| 文件命名     | 卡片文件名格式 `YYYYMMDD-HHMMSS.md`，不允许中文/空格 |
| index.json   | 单一权威索引，禁止手动编辑                           |
| skills/ 目录 | distill 草稿不直接写入，必须经人工移动               |
| reconcile    | 不回写源 agent 的 memory store                       |
| 归档         | 只改 STATUS 字段，不删除文件                         |
