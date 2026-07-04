---
name: importing-agent-prompts
description: 把外部 agent 的 system prompt 库(pi agent、Claude Code subagent、Codex/OpenCode/Aider 等的 .md 设定)搬进 Hermes 的 skill 系统。当用户提到 "把这些 agent 设定迁过来 / pi 的 agent 能用在 hermes 上吗 / 把 XX agent 的 prompt 搬过来 / 我有一堆其他 agent 的 markdown 配置 / 我不再用 XX 了但这些 prompt 有价值" 时触发。也涵盖 "提示词模板"、"review 提示词"、"把这段 prompt 注入到会话" 这类需求。
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [migration, agent-prompts, skill-creation, prompt-template, external-prompts]
    related_skills: [hermes-skill-curation, hermes-agent, worker-handoff]
---

# importing-agent-prompts — 把外部 agent 的 prompt 库搬进 hermes

管这一类工作:**用户手里有一堆来自其他 agent 框架的 markdown prompt(子 agent 设定、system prompt、role 模板),想迁移到 hermes 的 skill 系统,或者想知道它们在 hermes 里该怎么用**。

典型来源:

- pi agent 的 `~/Documents/pi/agents/*.md`(每个文件一个 subagent)
- Claude Code 的 `.claude/agents/*.md`(subagent 设定)
- Codex / OpenCode / Aider / Cline 等的自定义 agent
- 用户自己写的"review 提示词"、"规划模板"、"调研模板"等 markdown prompt
- 其他框架的 slash command(`.claude/commands/*.md`)

## 第一性原理:先判断这个 prompt 在 hermes 里**对应什么原语**

不要急着动手搬。先回答:**这个东西在 hermes 里是什么?**

| 需求 | hermes 原语 | 落地路径 |
|---|---|---|
| "用户问 X 时自动加载" | **skill**(description 自动匹配) | 改成 SKILL.md |
| "我手动 /skill 加载" | **skill** | 改成 SKILL.md,用户 `/skill name` 触发 |
| "作为子 agent 任务指令" | `delegate_task` 的 `context` | 保留为 markdown,主会话按需塞进 context |
| "整个项目持续生效" | **AGENTS.md / CLAUDE.md** | 拼接到项目级或全局级 instructions |
| "命令触发" | 原生 slash command / 自定义 slash | 需要写到 hermes 的 command registry |

**最常见也是最对路的归宿是 skill**。原因是:skill 一加载内容就成 system prompt,**整个 SKILL.md 本身就是一份完整的可复用 prompt** —— 想贴到别处直接 `cat` 或复制就行,何必再嵌一层 snippet。

## ⚠️ 核心设计教训(本次踩坑)

**不要在 SKILL.md 里写独立的 "Prompt Injection Snippet" / "可复制片段" 章节。**

`SKILL.md` 加载后**全文进入 system prompt**,它本身就是 prompt。任何把内容拆成"框架说明"和"可复制片段"两层的写法都是冗余。

正确做法:

- SKILL.md 全文就是 prompt(人格 + 工作流 + 输出模板 + 重要规则)
- 用户想拿去别处用 → `cat ~/.local/share/hermes/skills/<name>/SKILL.md` 完整复制
- 不要为了"既能加载又能复制"人为分层

反面教材(早期错误方案):

```markdown
## 风格定调
...

## 工作流
...

## Prompt Injection Snippet   ← ❌ 这层完全多余
复制下面的内容到任意对话窗口:
你是 XX,工作流是 YY...
```

正确写法:

```markdown
## 风格定调
...

## 工作流
...
(到这里就是完整 prompt,SKILL.md 本身就是)
```

## 迁移工作流(五步)

### 1. 摸清来源

列出所有源文件,按"角色定位"分组。常见角色:

- **侦察 / 阅读型**:scout、researcher、reader —— 只读分析
- **执行 / 写作型**:worker、implementer、coder —— 主动修改
- **规划 / 决策型**:planner、oracle、advisor —— 产出方案
- **审查 / 验证型**:reviewer、critic、auditor —— 对抗性验证
- **辅助 / 工具型**:visual、formatter、translator —— 单一职责

### 2. 逐个判定归宿(用第一性原理那张表)

每个 prompt 一行判定:

| 源文件 | 角色 | 归宿 | 理由 |
|---|---|---|---|
| scout.md | 只读侦察 | skill:`codebase-scout` | hermes 缺这个能力,自动触发价值高 |
| worker.md | 执行器 | skill:`worker-handoff` | 给主会话派发 delegate_task 用的规范 |
| visual.md | 视觉分析 | **弃用** | hermes 内置 `vision_analyze` / `browser_vision` 覆盖 |

### 3. 裁剪 pi/Claude 的元数据

需要删掉的(hermes 不认):

- `tier: ultra` / `tier: pro` / `tier: inherit`(pi 内部资源等级)
- `tools: read, grep, find, ls, write`(pi 的工具白名单,hermes 走 toolset)
- `<atelier:subagent>` / `<!-- /@atelier:subagent -->` HTML 块(pi 渲染指令)
- `.agents/workfile/{name}/` 持久化约定(改成 hermes 的输出:handoff 文本 + 显式 write_file)
- `## 通用部分(主会话和 subagent 都看)` 这种双视角分段(hermes 是单视角)

要保留的(语义层):

- 人格描述("你是 XX,你的工作是 YY")
- 工作流(风格定调 + 工作步骤)
- 输出格式模板
- 重要规则("每个质疑必须有替代建议" 这类不可妥协的硬约束)

### 4. 改写为 SKILL.md(hermes 格式)

```markdown
---
name: <lowercase-with-hyphens>
description: <一句话> —— <详细触发场景>。当用户说 "A / B / C" 时触发。
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [<3-5 个 tag>]
    related_skills: [<相关 skill 名列表>]
---

# <name> — <一句话定位>

## 风格定调

...

## 工作流

...

## 输出格式

```markdown
...
```

## 重要规则

1. ...
```

**description 的写法很关键** —— hermes 自动匹配全靠它。要:

- 用 "当用户说 X / Y / Z 时触发" 列具体短语
- 包含中英文同义词(review / 审查 / 看看 / check)
- 不要太宽泛(否则跟其他 skill 撞),也不要太窄(否则永远触发不了)

### 5. 落地并验证

写到 `$HERMES_HOME/skills/<name>/SKILL.md`(在 Nix 装的 hermes 上是 `~/.local/share/hermes/skills/`,不是 `~/.hermes/`)。

落地后必做的验证:

```bash
# 文件存在且 frontmatter 合规
head -10 ~/.local/share/hermes/skills/<name>/SKILL.md

# 在 hermes 里能查到
hermes skills list | grep <name>

# 触发测试(下次 /reset 后)
# 跟 description 里的触发短语说一句,看是否自动加载
```

## 批量迁移的节奏建议

不要一次全做完。推荐节奏:

1. **先做 1 个**:`code-reviewer` 或你最常会用的那个,验证格式和触发都对路
2. **再批量 2-3 个**:挑互相依赖少的(比如 scout、oracle、planner)
3. **最后单独处理特殊 case**:worker(派发规范类)、visual(可能直接弃用)
4. **每做一个实际用一次**:不要堆完才测试 —— 触发出问题 / 内容遗漏可以马上调

## 不适合做成 skill 的 prompt

- **极轻量的视觉约定**(42 行 visual.md 这种) —— 直接用 hermes 内置工具
- **只能跑一次的模板**(某个具体 PR 的脚本) —— 放到 `scripts/` 或 templates/ 而不是 skill
- **跟 hermes 已有 skill 完全重复的** —— 检查 `skills_list` 后再决定
- **来源不明的"提示词黑魔法"** —— 用户拿来但说不清用途的,先确认再搬

## 参考资料

- `references/pi-agent-migration.md` — 把 pi agent(`~/Documents/pi/agents/*.md`)7 个 subagent 搬进 hermes skill 的**完整实战记录**:逐文件归宿判定、裁剪清单、SKILL.md 样板、触发短语写法、落地步骤、已知陷阱

## 与 hermes-skill-curation 的边界

- **本 skill(importing-agent-prompts)**:把**外部资源**首次引入 hermes
- **hermes-skill-curation**:对**已有 skill 库**做整理(合并 / 归档 / 删除 / 审计)

如果用户问"我有一堆 pi agent 的 md,怎么搬到 hermes" → 用本 skill。
如果用户问"我 hermes 里 skill 太多了,哪些该删" → 用 hermes-skill-curation。

## 已验证的真实映射案例(pi agent → hermes skill)

| 源文件 | 归宿 | 自动触发关键词 |
|---|---|---|
| reviewer.md | `code-reviewer` skill | review / 审查 / 提 PR 前看看 / 这有什么问题 |
| scout.md | `codebase-scout` skill | 扫一下 / 找 X 在哪 / 摸清结构 |
| planner.md | `task-planner` skill | 帮我规划 / 拆解任务 / 制定方案 |
| oracle.md | `architecture-advisor` skill | 架构合不合理 / 更好方案 / 第二意见 |
| researcher.md | `doc-researcher` skill | 调研这个库 / 查 API / 版本兼容性 |
| worker.md | `worker-handoff` skill | 派发子任务 / 并行 worker(规范而非触发) |
| visual.md | **弃用** | 走 hermes 内置 `vision_analyze` |

## 重要规则

1. **先判定归宿再动手** —— 不是所有外部 prompt 都该变成 skill
2. **全文就是 prompt,不要再嵌 snippet 章节** —— 加载后整文都生效
3. **裁剪 pi/Claude 私有元数据** —— `tier` / `tools` / `<atelier:subagent>` / `.agents/workfile/` 全删
4. **description 必须列具体触发短语** —— 自动匹配全靠它
5. **一次做一个,做完实际触发测试** —— 别堆
6. **不强行套 hermes 工具**(比如硬把 pi 的视觉 subagent 改成 hermes skill,实际内置工具更合适)