---
name: agenote-base
description: agent 专属记事本（agenote）的基础使用指南。当需要记录查询所得知识、项目处理中遇到的问题、跨会话偏好时使用。涵盖 agenote MCP tool、卡片格式、何时记录/何时不记录。
---

# agenote — agent 专属记事本

agenote 是人类知识库（`~/Documents/Org/`）的**并行子集**，专为 AI agent 记录而设。数据隔离在 `~/Documents/Org/agenote/` 子目录，与人类卡片互不污染。

> **调用方式**：agenote 已改造为 MCP server，agent 主循环通过 MCP tool 调用（tool 名以 `agenote_` 为前缀）。pi-mcp-adapter lazy 连接，首次调用时自动启动 server。以下示例中的 `agenote_*` 均为 MCP tool 名。

> **来源溯源**：每张 agent 写入的卡片自动打 `:SOURCE_AGENT:` 标签（取自启动 env
> `AGENOTE_AGENT`，缺失回退 `pi`）。`agenote_health()` 的 `by_source` 字段可看各 agent
> 写卡分布；`agenote_search` 命中跨 agent 卡片时 `domain`/`source` 字段标注来源。
> 跨 agent 经验共享（reconcile/dream/distill）见 `agenote-curator` skill。

## 何时该记录

主动记录以下场景，减少重复劳动：

- **查询到的有用知识**：联网/文档查到的技术方案、API 用法、环境信息（写 `--type note`）
- **项目处理中的问题**：调试踩坑、被用户纠正、走了弯路（写 `--entry mistake`）
- **多轮试错的最优方案**：经历多次失败后找到的正确做法（写 `--entry ascended`）
- **跨会话偏好**：用户对 agent 工作方式的偏好（写 `memory --type feedback`）
- **项目特定约束**：某仓库的技术栈、构建命令、已知坑点（写 `memory --project`）

## 何时不该记录（避免噪音）

- 纯浏览未采用的资料（只记录实际用到的）
- 临时调试输出、可从代码直接推导的信息
- 一次性任务、不具复用价值的细节

## 核心命令（MCP tool）

```
# 初始化（仅首次）
agenote_init

# 添加卡片（note/mistake/ascended）
agenote_add(title="标题", entry="note", body="详细内容")

# 读取卡片（用 ID，不是 title；先 list/search 找 ID）
agenote_get(target="<ID>", used=true)      # used=true 留痕（USAGE_COUNT+1）

# 跨域加权检索（同时搜人类 + agent 卡片，人类权重更高）
agenote_search(query="关键词")

# 列出/统计/健康度
agenote_list()
agenote_stats()
agenote_health()

# 记忆系统
agenote_memory_add(title="偏好", mem_type="feedback", body="内容")
agenote_memory_overview()                   # 概览
agenote_memory_search(stale=true)           # 陈旧记忆

# 策展（健康+去重+归档+权重重分配）
agenote_curate()
```

## 可视化 — `kb viz` 就是体系内的 `md2html`

用户心智模型里常把"把 markdown 渲染成可视化网页"的工具叫 `md2html`，但**本机已装的对应物是 `kb viz`**（`~/.local/bin/kb` 的子命令，2014-2026 就在那里）。下次用户说"用 md2html"或"把 KB 渲染出来看"，先想 `kb viz`：

| 维度 | `kb viz`（已装）                                     | 通用 `md2html` skill |
| ---- | ---------------------------------------------------- | -------------------- |
| 输入 | `~/Documents/Org/index.json`（人类+agenote 索引）    | 单个 .md 文件        |
| 输出 | 单文件 HTML（≈87 KB，自带 dark/light/auto 主题）     | 单文件 HTML          |
| 交互 | 全文搜索 + 类别树 + 多维过滤 + 统计图 + 过期告警     | 仅渲染               |
| 启动 | `kb viz -o out.html` 或 `kb viz --serve --port 8765` | 取决于具体 skill     |

**何时用 `kb viz`**：内容是 KB 卡片、要检索/过滤/统计。
**何时退回 pandoc**：内容是单份 markdown 报告（KB 卡片化会丢失章节顺序），用 `pandoc -s <md> -o <html>` + 自写 CSS。

## 本机 agent 拓扑（2026-06-28 实测）

`agenote` 的写入者不止 pi/hayes。给一张现有 agent 系统清单，方便在 review/curate 时知道哪些 agent 的经验该入库：

| Agent           | 数据位置                           | MCP                                                  | 已有 agenote 桥接？                          |
| --------------- | ---------------------------------- | ---------------------------------------------------- | -------------------------------------------- |
| hermes-agent    | `~/.local/share/hermes/`           | ✅（已配 holographic + mcp-server-memory）           | 半（holographic 走 `fact_store`，没走 `kb`） |
| pi-coding-agent | `~/.pi/`（`$PI_CODING_AGENT_DIR`） | ✅                                                   | ✅（`agenote-hooks` 插件）                   |
| oh-my-pi (OMP)  | `~/.config/pi/omp/`                | ✅                                                   | ❌（用户偏好本仓库不托管 OMP 配置）          |
| crush           | `~/.config/crush/`                 | ✅（filesystem/memory/context7/sequential-thinking） | ❌                                           |
| opencode        | `~/.opencode-mem/data/*.db`        | 待确认                                               | ❌                                           |
| reasonix        | `~/.reasonix/`                     | 待确认                                               | ❌                                           |
| claude-code     | —（本机未检出 `~/.claude/`）       | ✅                                                   | ❌                                           |

**结论**：当前只有 pi 一个 agent **自动**往 agenote 写（经 `agenote-hooks` 插件 + MCP server）。其他 agent 要手动调 MCP tool 或 agenote_cli shim。

## 重要：用 ID 而非 title 定位卡片

`agenote_get`/`agenote_touch`/`agenote_archive` 等 tool 用 **ID 或文件名片段**匹配，不匹配 title。先用 `agenote_list` 或 `agenote_search` 找到卡片 ID（如 `20260625-014305`），再 `agenote_get(target="<ID>")`。

## ENTRY_TYPE 语义（agent 场景）

| ENTRY_TYPE | 何时使用                                   |
| ---------- | ------------------------------------------ |
| `note`     | agent 查询到的有用知识、参考方案、环境信息 |
| `mistake`  | agent 被用户纠正、走了弯路、误判需求       |
| `ascended` | agent 经历多次失败/重试后找到的正确做法    |

## 留痕机制（减少重复联网）

查询资料后，对**实际用到**的部分留痕：

- **已有卡片**（人类或 agenote）：`agenote_touch(target="<ID>")` 递增 USAGE_COUNT
- **联网新知识**：`agenote_add(type="note", ...)` 写新卡片留档

频繁使用的卡片在 `agenote_curate` 时权重提升，检索时排名更靠前。

## 详细参考

- [卡片格式与字段](references/card-format.md)
- [记忆系统模型](references/memory-model.md)
- [ENTRY_TYPE 语义映射](references/entry-types.md)
- [健康度评估范式](references/health-assessment.md) — 用户问"agenote 怎么样"时跑这四件套
- [可视化选型：pandoc vs kb viz](references/visualization-pandoc-vs-kb-viz.md) — markdown 报告转 HTML 的两条路径 + pandoc 的 CSS 注入坑
