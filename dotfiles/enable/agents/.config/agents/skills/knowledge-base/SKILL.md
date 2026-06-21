---
name: knowledge-base
description: Use when querying historical experience, searching patterns, or when encountering "kb search", "kb list", "kb get", "kb fields", "查询知识库", "kb memory --stale", "check patterns".
---

# Knowledge Base（只读）

通过 `kb` CLI **检索**人类维护的经验卡片和记忆索引。**AI Agent 只能读，不能写**——所有卡片和 MEMORY.org 由人类手动撰写。

## 路径

| 用途     | 路径                                 |
| -------- | ------------------------------------ |
| CLI 工具 | `~/.local/bin/kb`                    |
| 经验卡片 | `~/Documents/Org/experiences/`       |
| 记忆文件 | `~/Documents/Org/MEMORY.org`         |
| 项目记忆 | `~/Documents/Org/memories/projects/` |
| 机器索引 | `~/Documents/Org/index.json`         |

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

## MEMORY.org 查阅

MEMORY.org 是人类维护的统一记忆索引（feedback / project / reference 三节），在会话启动时自动注入上下文。Agent 可以额外用以下命令查阅：

```bash
# 获取当前项目记忆
kb memory --project .

# 查看陈旧记忆（>30 天未更新）
kb memory --stale
```

<critical>
**定位区分**：
- **MEMORY.org** — 人类的行为偏好/项目上下文/外部指针（不可从代码推导）
- **知识库卡片** — 可复用的技术知识（调试方案、配置技巧、工作流优化）
</critical>

## 维护命令（只读/校验）

```bash
kb lint            # 检查卡片格式（不改内容）
kb reindex         # 重建索引（卡片有新增时由人类执行）
```
