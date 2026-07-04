# pi agent → hermes skill 迁移实战参考

这是把 `/home/brokenshine/Documents/pi/agents/` 下 7 个 pi subagent 设定
搬进 hermes skill 系统的**真实执行记录**。下次遇到同类任务直接复用。

## 源文件清单

来自 pi 的 in-process subagent 设定,每个 `.md` 是一个独立 agent:

| 文件 | 角色定位 | 大小 |
|---|---|---|
| `oracle.md` | 架构顾问(只读,战略视角) | 4085 字节 |
| `planner.md` | 战略规划师(只读 + 写 plan 文本) | 7660 字节 |
| `researcher.md` | 文档检索专家(只读 + 写报告) | 3726 字节 |
| `reviewer.md` | 代码审查者(只读 + 写报告) | 14568 字节 |
| `scout.md` | 快速侦察员(只读) | 3885 字节 |
| `visual.md` | 视觉分析员(只读 + 直接分析图片) | 1261 字节 |
| `worker.md` | 自主执行者(可写代码) | 8103 字节 |

## 归宿判定(已验证)

| 源文件 | 归宿 | 理由 |
|---|---|---|
| reviewer.md | ✅ skill:`code-reviewer` | hermes 缺对抗性审查能力,自动触发价值高 |
| scout.md | ✅ skill:`codebase-scout` | hermes 没有专门的"扫仓库"流程 |
| planner.md | ✅ skill:`task-planner` | 跟 hermes 的 `todo` 系统天然契合 |
| oracle.md | ✅ skill:`architecture-advisor` | 战略第二意见能力 hermes 没有 |
| researcher.md | ✅ skill:`doc-researcher` | 调研场景比 `web` 工具更结构化 |
| worker.md | ✅ skill:`worker-handoff` | 给主会话派发 `delegate_task` 用的规范 |
| visual.md | ❌ 弃用 | hermes 有 `vision_analyze` / `browser_vision`,42 行内容无独立价值 |

## 需要从 pi 文件里裁掉的元数据

| 元数据 | 来源 | 为什么删 |
|---|---|---|
| `tier: ultra / pro / quick / visual / inherit` | pi YAML frontmatter | hermes 不读这个,pi 内部资源等级 |
| `tools: read, grep, find, ls, write, bash` | pi YAML frontmatter | hermes 走 toolset 系统,不认这个白名单 |
| `<!-- @atelier:subagent --> ... <!-- /@atelier:subagent -->` | pi HTML 注释块 | pi 渲染指令,hermes 没这个分隔语义 |
| `.agents/workfile/{agent}/{YYYY-MM-DD}-{slug}.md` | pi 持久化约定 | hermes 的输出是 handoff 文本回主会话 + 显式 `write_file` 写用户指定路径 |
| `## 通用部分(主会话和 subagent 都看)` 双视角分段 | pi 章节设计 | hermes 是单视角 prompt,没有"主/子"分裂 |

## hermes SKILL.md 模板(从 pi 改造的样板)

```markdown
---
name: <lowercase-with-hyphens>
description: <一句话定位> —— <详细说明>。当用户说 "A / B / C" 时触发。
version: 1.0.0
license: MIT
metadata:
  hermes:
    tags: [<3-5 个 tag,逗号分隔>]
    related_skills: [<相关 skill 名列表>]
---

# <name> — <一句话定位>

## 风格定调

<从 pi 的 "## 工作风格" 章节搬运,简化为一段话>

## 工作流程

<从 pi 的 "## 工作流程" 章节搬运,改成编号列表>

## 输出格式

```markdown
<从 pi 的 "## 输出格式" 章节原样搬,hermes 同样能渲染代码块>
```

## 重要规则

1. <从 pi 的 "## 重要规则" 章节搬运>
2. ...

## 与其他 skill 的协作(可选)

<如果这个 skill 是流水线一环,显式说明上下游>
```

## description 触发的实战模板

hermes 自动匹配全靠 description 里的触发短语。实战写法:

**好写法**:

> 严格的代码审查助手 —— 对代码 diff、文件、PR 或整个模块做基于证据的对抗性审查,覆盖架构、代码质量、工程实践、性能与安全四维。当用户说 "review/审查/检查这段代码"、"看看我写的对不对"、"code review"、"提 PR 前帮我看看"、"这有什么问题"时触发。

要点:

- 第一句: 一句话定位(名词为主)
- 破折号后: 详细能力描述
- 末尾: 列具体触发短语,**中英文并列**,**多种口语化说法**
- 3-5 句足够,不要塞太多

**反面**:

> 描述太宽泛:"一个有用的助手"——会跟所有 skill 撞
> 描述太技术:"四维 Linus Torvalds 风格对抗性审查"——用户不会这么说话
> 没有触发短语:hermes 不知道什么时候加载

## 落地路径

**重要**:在 Nix 装的 hermes 上,skills 目录是 `~/.local/share/hermes/skills/`,**不是 `~/.hermes/skills/`**。

落地后必做:

```bash
# 1. 文件存在
ls ~/.local/share/hermes/skills/<name>/SKILL.md

# 2. hermes 能发现
hermes skills list | grep <name>

# 3. 在 hermes CLI 里试触发
hermes chat -q "review 这段代码: <paste>"
# 观察 system prompt 里是否自动加载了 code-reviewer
```

## 完整执行清单(下次照抄)

1. 列出所有源文件,按角色分组
2. 逐个判定归宿(skill / delegate_task 模板 / 弃用)
3. 对每个变成 skill 的:
   - 提取 frontmatter(name / description / version / license / metadata.hermes.tags / related_skills)
   - 删 pi 私有元数据
   - 章节扁平化(去掉双视角分段)
   - description 改写成触发短语形式
4. 写到 `~/.local/share/hermes/skills/<name>/SKILL.md`
5. `hermes skills list` 验证发现
6. 实际触发一次验证 description 匹配

## 已知陷阱

1. **description 没触发短语** → 用户永远加载不了这个 skill
2. **保留了 pi 的 `.agents/workfile/{agent}/` 路径** → hermes 没这个目录,worker 写报告时会失败
3. **保留了 `tools:` 白名单** → hermes 不解析,工具反而受限
4. **skill 内容太长** → 自动加载会污染 system prompt,只保留核心工作流,详细规则放 `references/`
5. **忘了 `license: MIT`** → 校验可能失败(虽然不一定 fatal)