---
name: knowledge-base
description: 知识库操作工具 — 通过 kb CLI 检索、写入、管理经验卡片和模式
version: "2.0.0"
when_to_use: |
  Use when you need to interact with the knowledge base via kb CLI.
  Triggers: "kb search", "记录经验", "写入知识库", "kb add",
  "search experiences", "check patterns", "检索历史经验",
  "任务开始前检索相关经验", "write to knowledge base",
  "查一下之前怎么解决的", "有没有类似经验", "记录下来",
  "这个值得记住", "add to kb", "查询知识库"
allowed-tools:
  - Read
  - Bash(kb:*)
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

- `kb list` 默认显示最近 20 条，`--all` 显示全部
- `kb list` 输出格式：`文件路径|标题|类别|类型|执行者|日期`
- `kb search` 输出为匹配行及上下文，格式：`文件名-行号-:内容`

### 字段统计（优先复用标签）

```bash
kb fields              # 列出所有已有 category/tech/type/owner
kb fields --category   # 只列出已有 category
kb fields --tech       # 只列出已有 tech
```

写入前先查看已有标签，优先复用，减少碎片化。

### 写入

```bash
kb add \
  --title "简明标题" \
  --category <类别> \
  --tech <技术栈> \
  --type <类型> \
  --owner <执行者> \
  --entry <mistake|note|ascended> \
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

参数取值详见 `references/parameters.md`。

### 纠错 / 记事条目映射

Mistakebook 的 `mistake` / `note` 语义统一写入本知识库，不再另建并行存储。CLI 支持 `kb add --entry mistake|note|ascended`，会自动补 `ENTRY_TYPE` 属性、标签和默认模板；若 `--stdin` 内容已经包含 `**` 小节，则按完整 Org 正文原样写入。

| 来源语义     | 推荐 type                          | 推荐 owner             | 必须保留的信息                           |
| ------------ | ---------------------------------- | ---------------------- | ---------------------------------------- |
| `mistake`    | `debug` / `config`                 | `collaborative`        | 原始问题、纠错反馈、错因、最终答案、自检 |
| `note`       | `workflow` / `research` / `config` | `ai` / `collaborative` | 事项内容、记录原因、适用边界、行动项     |
| 飞升模式复盘 | `debug` / `workflow`               | `collaborative`        | 失败原因、检索来源、最强方案、后续规则   |

纠错类卡片可在标准三段内增加 Org 子标题：

```org
** 任务描述
原始问题、用户纠错反馈链。

** 执行过程
*** 这次到底错在哪里
...
*** 最终正确处理
...

** 关键发现
*** 下次开始前自检
+ ...
```

记事类卡片至少写清：

1.  为什么值得长期保留
2.  适用场景与例外
3.  后续行动或检查点

### 写入前决策

1.  先 `kb search` 去重；已有卡片覆盖时优先补充或修正，不新建重复卡
2.  **优先复用已有标签** — `category` 和 `tech` 不设白名单，但写入前应查看现有标签（`kb list`），优先复用已有类别；只有全新领域才创建新类别
3.  项目私有细节只写入必要上下文；可泛化规则再晋升到 `patterns.org`
4.  卡片保存完整过程，pattern 保存紧凑规则；二者可以共存，pattern 必须引用卡片 ID

### 查看

```bash
kb get <卡片ID或文件名>   # 查看完整内容（ID 即文件名前的时间戳，如 20260423-230246）
kb patterns               # 列出所有模式标题
kb patterns --get         # 显示模式全文
```

### 管理

```bash
kb patterns --add <<'EOF'
** <结论性标题>
   <一句话声明式规则>。
   适用：<场景>
   例外：<反例或边界条件>
   参考：<经验卡片 ID>
EOF

kb reindex   # 重建索引（新增/删除卡片后运行）
```

**模式写入规范**：模式是紧凑的声明式规则，非排查叙事。标题为结论，正文 ≤5 行。必须包含"适用/例外/参考"三个字段。

## 格式规范（CRITICAL）

卡片格式为 **Org mode**，不是 Markdown。写入 `--stdin` 内容时必须遵守以下规则：

### 代码块 — 用 `#+begin_src`，禁止 ` ``` `

错误（Markdown）：

````markdown
```elisp
(message "hello")
```
````

正确（Org mode）：

```org
#+begin_src elisp
(message "hello")
#+end_src
```

### 强调 — 用 `*text*`，禁止 `**text**`

错误：`**粗体**`

正确：`*粗体*`

注意：`** 任务描述`（`**` 后有空格）是 Org 二级标题，不是粗体。

### 标题层级

```org
* DONE 标题
** 任务描述
*** 子章节
```

`kb add` 自动生成一级标题；`--stdin` 中从二级标题开始写。

### 写入后校验

写入后必须运行 `kb lint` 检查格式：

```bash
kb lint            # 检查所有卡片
kb lint --fix      # 自动修复
```

### Markdown → Org 速查表

| Markdown        | Org mode                         | 说明     |
| --------------- | -------------------------------- | -------- |
| ` ```lang ``` ` | `#+begin_src lang ... #+end_src` | 代码块   |
| `**bold**`      | `*bold*`                         | 粗体     |
| `## heading`    | `*** heading`                    | 子标题   |
| `- item`        | `+ item`                         | 无序列表 |
| `` `code` ``    | `~code~`                         | 行内代码 |
