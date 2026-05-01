# 知识库策展工作流指南

## 记忆分层模型

借鉴 Hermes 记忆系统，知识库内容按三层分类：

| 层级     | Hermes 对应    | 存储位置                         | 内容                                        |
| -------- | -------------- | -------------------------------- | ------------------------------------------- |
| 经验卡片 | memory         | `~/Documents/Org/experiences/`   | 跨会话可复用的 bug 修复、配置陷阱、方案对比 |
| 模式文件 | skill          | `~/Documents/Org/patterns.org`   | 3 次以上同类经验的通用规则、预防性指导      |
| 对话历史 | session_search | `~/Documents/Org/conversations/` | 任务进度、TODO、一次性操作记录              |

### 分层决策标准

写入经验卡片前，先判断：

- **这是否是跨会话可复用的知识？** 是 → 经验卡片；否 → 继续判断
- **这是否是通用规则/模式？** 是 → 模式文件；否 → 经验卡片
- **一次性任务进度？** → 留在对话历史，不写入知识库

## 策展流程

```
0. 提取对话 → 1. 诊断 → 2. 筛选 → 3. 补充 → 4. 重整 → 5. 提交
```

### 第〇步：提取对话（夜间策展必做）

使用 `extract-conversations.py` 从所有 AI 编程工具提取昨日对话：

```bash
python3 scripts/extract-conversations.py -o ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)
```

此脚本自动覆盖 4 个数据源（OpenCode / Crush / Claude Code / Codex），输出 Org-mode 格式对话文件。
提取完成后浏览输出目录，标记有记录价值的对话文件。

### 第一步：诊断（analyze_kb.py）

运行 `analyze_kb.py --quality --duplicates`，获取知识库整体健康报告。

关注指标：

- **类别分布极度不均**：某类别 >50% 总量 → 考虑拆分或补充其他类别
- **类型分布偏斜**：debug/config 占比过高时，考虑提炼 workflow/refactor 类经验
- **重复卡片**：重叠率 >80% 且同类别 → 合并或删除旧卡
- **质量缺陷**：缺少执行过程/关键发现的卡片 → 补充或降级

### 第二步：筛选（find_gaps.py）

运行 `find_gaps.py --stale-days 60`，识别待处理内容。

筛选维度：

- **缺失组合**：存在的类别缺少某些类型的卡片 → 优先补充
- **完全空白类别**：python/rust/android 等无任何卡片 → 从对话历史中提取
- **薄弱领域**：卡片数 ≤2 的类别 → 分析原因，是确实不需要还是未记录
- **陈旧卡片**：超过 60 天未更新的卡片 → 评估是否仍然准确
- **纯 AI 类别**：无人参与的类别 → 考虑添加人工审核笔记

### 第三步：补充

三种补充来源：

#### A. 从对话历史提取

首选 `extract-conversations.py` 自动提取，然后手动浏览：

```bash
# 提取昨日所有数据源的对话
python3 scripts/extract-conversations.py -o ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)

# 浏览提取的文件
ls ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)/

# 搜索包含错误/修复关键词的对话
grep -rl "fix\|bug\|error\|解决\|修复" ~/Documents/Org/conversations/$(date -d yesterday +%Y-%m-%d)/ | head -10
```

#### B. 从模式文件提炼

`~/Documents/Org/patterns.org` 中的模式如有对应经验缺失，需要补充具体案例卡片。

#### C. 从收件箱整理

`~/Documents/Org/inbox.org` 如有点子/待办，评估是否值得转为正式卡片。

### 第四步：重整

补充完成后必须执行：

```bash
kb reindex     # 重建索引
kb-lint        # 格式检查
kb-lint --fix  # 自动修复格式问题
```

### 第五步：提交

变更涉及的文件：

- `~/Documents/Org/experiences/` 下的新增/修改卡片
- `~/Documents/Org/index.org`（kb reindex 自动更新）
- 可选：`~/Documents/Org/patterns.org`

**重要规则**：

- 只提交本次策展涉及的文件
- 不要提交无关的对话文件或模式文件
- 提交前运行 `kb-lint --fix` 确保格式正确

## 质量评判标准

### 合格卡片应满足

- [ ] 有明确的 CATEGORY / TECH / TYPE / OWNER 元数据
- [ ] 任务描述：一句话说清楚做了什么、为什么
- [ ] 执行过程：包含背景、根因、方案、验证
- [ ] 关键发现：≥1 条可复用的经验教训
- [ ] 使用 Org mode 格式（非 Markdown）
- [ ] 代码块用 `#+begin_src`，不用 ` ``` `
- [ ] 标题为声明式结论（"X 情况下 Y 导致 Z"），非指令（"总是要..."）
- [ ] 记录的是坑点/教训，而非任务流水账

### 低质卡片特征

- 只有标题没有正文
- 执行过程中只有结论没有过程
- 缺少关键发现/经验教训
- 格式错误（Markdown 污染）
- 标题为指令式（"Always do X"）而非声明式
- 内容为一次性任务进度，无可复用价值
- 与已有卡片高度重复（重叠率 > 80%）

## 补充策略优先级

| 优先级 | 场景                 | 行动                                |
| ------ | -------------------- | ----------------------------------- |
| P0     | 完全空白的类别       | 从对话历史 + 最近工作提取           |
| P1     | 已有类别缺关键类型   | 补充缺失类型的卡片                  |
| P2     | 薄弱领域（≤2 张）    | 回顾该领域工作，补录经验            |
| P3     | 质量缺陷卡片         | 补充缺失章节、修复格式              |
| P4     | 纯 AI 类别缺人类视角 | 添加 human/collaborative owner 卡片 |
| P5     | 陈旧卡片             | 评估是否需要归档或更新              |
