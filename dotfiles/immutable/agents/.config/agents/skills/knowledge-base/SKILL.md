---
name: knowledge-base
description: Use when querying historical experience, writing new experience cards, searching patterns, or when encountering "kb search", "记录经验", "写入知识库", "check patterns", "kb add", "kb list", "kb fields".
---

# Knowledge Base

通过 `kb` CLI 管理经验卡片和模式，实现任务间知识复用。卡片为 Org mode 格式，按 category 子目录存储在 `~/Documents/Org/experiences/`。

> 经验写入时的决策逻辑、分类映射、卡片结构规范及用户画像维护流程见 `self-improving` skill。

## 路径

| 用途     | 路径                           |
| -------- | ------------------------------ |
| CLI 工具 | `~/.local/bin/kb`              |
| 经验卡片 | `~/Documents/Org/experiences/` |
| 模式文件 | `~/Documents/Org/patterns.org` |
| 机器索引 | `~/Documents/Org/index.json`   |
| 收件箱   | `~/Documents/Org/inbox.org`    |
| 用户画像 | `~/Documents/Org/profile.org`  |

## 检索

```bash
# 任务前预检第一步：按领域列出所有标题和元数据
kb list --category <类别> --all

# 全文检索：默认多关键词相关度检索，大小写不敏感
kb search "<关键词 工具 症状>" [--context N] [--limit N]

# 只接受包含所有关键词的结果
kb search "<关键词 工具 症状>" --all-terms [--context N]

# 旧式正则检索
kb search --regex "<正则>" [--context N]

# 按标签筛选
kb tags <标签> [标签2 ...]

# 查看标题和id（默认最近 20 条；领域预检必须加 --all）
kb list [--category 类别] [--type 类型] [--owner 执行者] [--recent N] [--all]

# 查看完整内容
kb get <卡片ID或文件名>

# 列出模式标题
kb patterns

# 显示模式全文
kb patterns --get
```

任务前预检优先用 `kb list --category <类别> --all` 获取该领域全部卡片标题和元数据，再根据标题对明显相关卡片执行 `kb get <id>`。只有标题列表不足以定位时，再用 `kb search` 做正文检索。

`kb search` 默认会按空格、`/`、逗号拆分多个关键词，按命中词数、标题命中和出现次数排序。Agent 做正文检索时优先给出 2-5 个具体关键词，不要把整句自然语言问题直接丢进去；需要精确正则时显式使用 `--regex`。

`kb list` 输出 JSON 数组，每项含 `id`、`title`、`category`、`type`、`tech`、`owner`、`created`。默认最近 20 条，`--all` 显示全部。

## 字段统计

```bash
kb fields              # 所有已有 category/tech/type/owner
kb fields --category   # 只列 category
kb fields --tech       # 只列 tech
```

写入前先查看已有标签，优先复用，减少碎片化。

## 写入

```bash
kb add --title "标题" --category <类别> --tech <技术栈> \
  --type <类型> --owner <执行者> \
  [--entry mistake|note|ascended] --summary "总结" --stdin <<EOF
** 任务描述
...

** 执行过程
...

** 关键发现
...
EOF
```

参数取值详见 `references/parameters.md`

具体的样板参见 `references/experience-template.org`

## 管理

```bash
kb update <ID> --status done                                   # 更新状态
kb update <ID> --append-to "关键发现" --append-text "新发现"   # 追加内容

kb update <ID> --stdin <<EOF                                   # 追加内容
EOF

kb connect <卡片A> <卡片B> --desc "描述"                       # 双向链接

kb patterns --add <<'EOF'                                      # 追加模式
** <结论性标题>
   <一句话声明式规则>。
   适用：<场景>
   例外：<反例或边界条件>
   参考：<经验卡片 ID>
EOF

kb inbox "待捕获的想法"                                         # 快速捕获
kb stats                                                        # 统计概览
kb reindex                                                      # 重建索引
```

## 写入后校验

```bash
kb lint            # 检查所有卡片
kb lint --fix      # 自动修复
```

lint 规则详见 `references/markdown-to-org.md`，非必要不查看，请直接使用工具来进行相关操作。

## 用户画像

```bash
kb profile                           # 概览
kb profile <分类名>                  # 查看指定分类
kb profile --add "目标" --text "..."  # 追加条目
echo "- 新内容" | kb profile --set "偏好"  # 覆盖分类
```

## 子章节规则

`kb add` 自动生成一级标题；`--stdin` 中从二级标题开始写。
