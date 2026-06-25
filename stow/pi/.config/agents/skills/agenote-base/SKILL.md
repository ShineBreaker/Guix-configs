---
name: agenote-base
description: agent 专属记事本（agenote）的基础使用指南。当需要记录查询所得知识、项目处理中遇到的问题、跨会话偏好时使用。涵盖 kb agenote 子命令、卡片格式、何时记录/何时不记录。
---

# agenote — agent 专属记事本

agenote 是人类知识库（`~/Documents/Org/`）的**并行子集**，专为 AI agent 记录而设。数据隔离在 `~/Documents/Org/agenote/` 子目录，与人类卡片互不污染。

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

## 核心命令

```bash
# 初始化（仅首次）
kb agenote init

# 添加卡片（note/mistake/ascended）
echo "详细内容" | kb agenote add --title "标题" --entry note --stdin

# 读取卡片（用 ID，不是 title；先 list/search 找 ID）
kb agenote get <ID> --used      # --used 留痕（USAGE_COUNT+1）

# 跨域加权检索（同时搜人类 + agent 卡片，人类权重更高）
kb agenote search "关键词"

# 列出/统计/健康度
kb agenote list
kb agenote stats
kb agenote health

# 记忆系统
echo "内容" | kb agenote memory --add --type feedback --title "偏好" --stdin
kb agenote memory                # 概览
kb agenote memory --stale        # 陈旧记忆

# 策展（健康+去重+归档+权重重分配）
kb agenote curate
```

## 重要：用 ID 而非 title 定位卡片

`get`/`touch`/`update` 等命令用 **ID 或文件名片段**匹配，不匹配 title。先用 `list` 或 `search` 找到卡片 ID（如 `20260625-014305`），再 `get <ID>`。

## ENTRY_TYPE 语义（agent 场景）

| ENTRY_TYPE | 何时使用                                   |
| ---------- | ------------------------------------------ |
| `note`     | agent 查询到的有用知识、参考方案、环境信息 |
| `mistake`  | agent 被用户纠正、走了弯路、误判需求       |
| `ascended` | agent 经历多次失败/重试后找到的正确做法    |

## 留痕机制（减少重复联网）

查询资料后，对**实际用到**的部分留痕：

- **已有卡片**（人类或 agenote）：`kb agenote touch <ID>` 递增 USAGE_COUNT
- **联网新知识**：`kb agenote add --type note` 写新卡片留档

频繁使用的卡片在 `curate` 时权重提升，检索时排名更靠前。

## 详细参考

- [卡片格式与字段](references/card-format.md)
- [记忆系统模型](references/memory-model.md)
- [ENTRY_TYPE 语义映射](references/entry-types.md)
