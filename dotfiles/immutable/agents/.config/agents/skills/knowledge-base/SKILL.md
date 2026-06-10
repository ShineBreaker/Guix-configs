---
name: knowledge-base
description: Use when querying historical experience, writing new experience cards, searching patterns, or when encountering "kb search", "记录经验", "写入知识库", "check patterns", "kb add", "kb list", "kb fields".
---

# Knowledge Base

通过 `kb` CLI 管理经验卡片和模式，实现任务间知识复用。卡片为 Org mode 格式，按 category 子目录存储在 `~/Documents/Org/experiences/`。

> 经验写入时的决策逻辑、分类映射、卡片结构规范见 `self-improving` skill。

## 初始化

当 `~/Documents/Org` 不存在或为空时，引导用户运行：

```bash
kb init            # 创建目录结构 + git 仓库 + 初始 commit
kb init --no-git   # 仅创建目录结构，跳过 git
```

`kb init` 会创建完整的目录结构（experiences/、memories/projects/）、模板文件（MEMORY.org、inbox.org、.gitignore）并执行 git init + 初始 commit。

如果知识库已有内容，`kb init` 会安全退出并提示。

## 路径

| 用途     | 路径                                 |
| -------- | ------------------------------------ |
| CLI 工具 | `~/.local/bin/kb`                    |
| 经验卡片 | `~/Documents/Org/experiences/`       |
| 记忆文件 | `~/Documents/Org/MEMORY.org`         |
| 项目记忆 | `~/Documents/Org/memories/projects/` |
| 机器索引 | `~/Documents/Org/index.json`         |
| 收件箱   | `~/Documents/Org/inbox.org`          |

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
kb commit -m "一句话总结"                                       # 提交变更到 git
```

## 写入后校验

```bash
kb lint            # 检查所有卡片
kb lint --fix      # 自动修复
```

lint 规则详见 `references/markdown-to-org.md`，非必要不查看，请直接使用工具来进行相关操作。

## 子章节规则

`kb add` 自动生成一级标题；`--stdin` 中从二级标题开始写。

## 记忆系统

MEMORY.org 是统一记忆索引，通过 `kb memory` 管理，区分于知识库（`kb add/list/search`）。

<critical>
**长度硬约束**：MEMORY.org 会被完整注入 LLM 上下文，**每条 memory 只能写一句话**（声明式规则 + 关键命令/路径），不允许"现象+原因+策略+适用+例外+关联"多段结构。

**为什么**：
+ MEMORY.org 通常 100-200 行，完整注入大幅消耗上下文窗口
+ 偏好/规则本身用一句话足够；长描述是 KB 卡片的工作
+ 多段结构让 LLM 难以快速 grasp 核心规则

**如何压缩**：
+ 内容超过 1 句 → 拆为"摘要（一句话）+ 详细指向 KB 卡片 ID"
+ 现象/原因/策略/适用/例外/关联 → 全部移到 KB 卡片，memory 只保留声明式规则
+ 历史多行条目同样适用本规则：迁移到 KB 卡片后 memory 压为 1 句

**反例**（不允许）：
#+begin_src org
   ** F002 大任务分解并行
   单线程长思考在面对大量写入操作时效率极低。
   glm-5.1 将 258 项翻译任务分为 4 chunk 并行委托...
   策略：先规划 → 按模式分块 → 并行委托 → 汇总验证。
   适用：批量翻译、批量文件修改、批量配置生成...
   例外：任务间有严格依赖顺序时不可并行。
#+end_src

**正例**（一句话）：
#+begin_src org
   ** F002 大任务分解并行
   写入密集型任务先规划→按模式分块→N 个 worker 并行委托→汇总验证（commit 除外必须 serial），依赖任务不可并行。
#+end_src
</critical>

### 定位区分

- **MEMORY**：癖好/偏好/行为规则/项目上下文（不可从代码推导）
- **知识库**：可复用的技术知识（调试方案、配置技巧、工作流优化）

### 常用命令

```bash
# 获取当前项目记忆（任务开始时执行）
kb memory --project .

# 添加反馈记忆
kb memory --add --type feedback --title "标题" --stdin <<EOF
正文
EOF

# 添加项目记忆
kb memory --add --type project --project <项目名> --title "标题" --stdin <<EOF
正文
EOF

# 查看陈旧记忆
kb memory --stale

# 更新记忆时间戳
kb memory --touch F001
```

### 向后兼容

```bash
kb patterns           # → kb memory --type feedback（列出偏好标题）
kb patterns --add     # → kb memory --add --type feedback --stdin
kb patterns --get     # → 输出 MEMORY.org 的 * feedback 节
```
