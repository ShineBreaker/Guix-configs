---
name: knowledge-base
description: 知识库操作工具 — 通过 kb CLI 检索、写入、管理经验卡片和模式
when_to_use: |
  Use when you need to interact with the knowledge base (kb CLI).
  Examples: "kb search X", "记录经验", "写入知识库", "kb add",
  "search experiences", "check patterns", "检索历史经验",
  "任务开始前检索相关经验", "write to knowledge base"
allowed-tools:
  - Read
  - Bash(kb:*)
  - Bash(kb-lint:*)
  - Bash(kb\ search:*)
  - Bash(kb\ add:*)
  - Bash(kb\ list:*)
  - Bash(kb\ tags:*)
  - Bash(kb\ get:*)
  - Bash(kb\ patterns:*)
  - Bash(kb\ reindex:*)
---

# Knowledge Base

通过 `~/.local/bin/kb` 管理经验卡片和模式，实现任务间知识复用。

卡片格式为 Org mode，存储在 `~/Documents/Org/experiences/`，每张卡片包含元数据（ID、类别、技术栈、类型、执行者）和结构化正文（任务描述、执行过程、关键发现）。

## 路径

| 用途     | 路径                           |
| -------- | ------------------------------ |
| CLI 工具 | `~/.local/bin/kb`              |
| 经验卡片 | `~/Documents/Org/experiences/` |
| 模式文件 | `~/Documents/Org/patterns.org` |
| 索引文件 | `~/Documents/Org/index.org`    |

## 命令速查

### 检索

```bash
kb search "<关键词或正则>" [--context N]   # 全文检索，--context 控制上下文行数
kb tags <标签> [标签2 ...]                  # 按标签（category/type/owner/tech）筛选
kb list [--category 类别] [--type 类型] [--owner 执行者] [--recent N] [--all]
```

- `kb list` 默认显示最近 10 条，`--all` 显示全部
- `kb list` 输出格式：`文件路径|标题|类别|类型|执行者|日期`
- `kb search` 输出为匹配行及上下文，格式：`文件名-行号-:内容`

### 写入

```bash
kb add \
  --title "简明标题" \
  --category <类别> \
  --tech <技术栈> \
  --type <类型> \
  --owner <执行者> \
  --summary "一句话总结" \
  --stdin <<EOF
** 任务描述
简要说明要做什么、为什么。

** 执行过程
1. 分析与排查
2. 修复方案
3. 验证结果

** 关键发现
- 重要的经验教训或注意事项
EOF
```

参数取值详见 `${CLAUDE_SKILL_DIR}/references/parameters.md`。

### 查看

```bash
kb get <卡片ID或文件名>   # 查看完整内容（ID 即文件名前的时间戳，如 20260423-230246）
kb patterns               # 列出所有模式标题
kb patterns --get         # 显示模式全文
```

### 管理

```bash
kb patterns --add <<EOF
** 模式名称
   描述内容和适用场景。
EOF

kb reindex   # 重建索引（新增/删除卡片后运行）
```

## 格式规范（CRITICAL）

卡片格式为 **Org mode**，不是 Markdown。写入 `--stdin` 内容时必须遵守以下规则：

### 代码块 — 用 `#+begin_src`，禁止 ` ``` `

````
❌ 错误 (Markdown):
```elisp
(message "hello")
````

✅ 正确 (Org mode):
#+begin_src elisp
(message "hello")
#+end_src

```

### 强调 — 用 `*text*`，禁止 `**text**`

```

❌ 错误: **粗体**
✅ 正确: *粗体*

```

注意：`** 任务描述`（`**` 后有空格）是 Org 二级标题，不是粗体。

### 标题层级

```

- DONE 标题 ← 一级（kb add 自动生成）
  ** 任务描述 ← 二级（kb add 自动生成）\*** 子章节 ← 三级（执行过程中的分段标题）

````

### 写入后校验

写入后必须运行 `kb-lint` 检查格式：
```bash
kb-lint            # 检查所有卡片
kb-lint --fix      # 自动修复
````

### Markdown → Org 速查表

| Markdown        | Org mode                         | 说明     |
| --------------- | -------------------------------- | -------- |
| ` ```lang ``` ` | `#+begin_src lang ... #+end_src` | 代码块   |
| `**bold**`      | `*bold*`                         | 粗体     |
| `## heading`    | `*** heading`                    | 子标题   |
| `- item`        | `+ item`                         | 无序列表 |
| `` `code` ``    | `~code~`                         | 行内代码 |
