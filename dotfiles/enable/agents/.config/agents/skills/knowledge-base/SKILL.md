---
name: knowledge-base
description: Use when querying historical experience, searching patterns, or when encountering "kb search", "kb list", "kb get", "kb fields", "查询知识库", "check patterns".
---

# Knowledge Base（只读）

通过 `kb` CLI **检索**人类维护的经验卡片。**AI Agent 只能读，不能写**——所有卡片由人类在 Emacs 中手动编辑。

> 偏好/项目上下文由 Hermes 自带的 `memory` 工具管理（不再使用 MEMORY.org）。

## 路径

| 用途     | 路径                           |
| -------- | ------------------------------ |
| CLI 工具 | `~/.local/bin/kb`              |
| 经验卡片 | `~/Documents/Org/experiences/` |
| 机器索引 | `~/Documents/Org/index.json`   |

## 检索（核心流程）

### 任务前预检

<critical>
开始任何非平凡任务前，必须先执行 `kb list --category <category> --all` 读取对应领域标题索引。标题列表不足以定位时，再执行 `kb search` 正文预检。
</critical>

```bash
# 第一步：按领域列出所有标题和元数据
kb list --category <类别> --all

# 第二步：读明显相关的卡片全文
kb get <卡片ID或文件名>

# 第三步（标题索引不够时）：正文检索
kb search "<关键词 工具 症状>" [--context N] [--limit N]
kb search "<关键词 工具 症状>" --all-terms    # 只接受包含所有关键词的结果
kb search --regex "<正则>" [--context N]      # 精确正则
```

`kb list` 输出 JSON 数组，每项含 `id`、`title`、`category`、`type`、`tech`、`owner`、`created`。默认最近 20 条，`--all` 显示全部。

`kb search` 按空格、`/`、逗号拆分多关键词，按命中词数、标题命中和出现次数排序。Agent 优先给出 2-5 个具体关键词，不要把整句自然语言直接丢进去；需精确正则时才用 `--regex`。

### 辅助查询

```bash
# 按标签筛选
kb tags <标签> [标签2 ...]

# 查看已有 category/tech/type/owner（帮助理解知识库结构）
kb fields
kb fields --category
kb fields --tech

# 统计概览
kb stats

# 列出模式标题（已归纳的通用规则）
kb patterns

# 显示模式全文
kb patterns --get
```

### 结果处理

- **高相关** → 作为上下文参考
- **低相关/空** → 静默继续
- **矛盾** → 以较新/验证过的为准

## 维护命令（只读/校验）

```bash
kb lint            # 检查卡片格式（不改内容）
kb reindex         # 重建索引（卡片有新增时由人类执行）
```
