# agenote-write-patterns — KB 写入的 entry 类型选择

来源：agenote base 的 `entry` 字段语义 + punkjazz.ai "independent review prevents over-broad lesson"。

## entry 三种语义

### note（观察到的事实/模式）

**适用**：
- 跨项目可复用的 workflow pattern
- "在 X 场景下，Y 模式 work" 这种**经验沉淀**
- 不带强烈情感判断

**反例**（不该写 note）：
- "我喜欢 X" → 走 memory / user
- "X 错了，X 是错的" → 走 mistake
- "X 是最优方案" → 走 ascended（需 evidence）

**模板**：

```org
* DONE <title>
:PROPERTIES:
:ID:       <timestamp>
:CREATED:  [<date>]
:CATEGORY: <category>
:TECH:     <tech>
:TYPE:     workflow|debug|knowledge|note
:ENTRY_TYPE: note
:WEIGHT:   1.0
:SOURCE_AGENT: hermes
:USAGE_COUNT: 0
:END:

* 上下文
<为什么这个 fact 重要>

* 观察
<看到了什么>

* 模式
<可复用的 pattern>

* Evidence
<commit / 命令输出 / 路径>

* Related
<与其他卡片的关系>
```

### mistake（踩过的坑 + 怎么避）

**适用**：
- "我做了 X，结果 Y 错了，下次别做" 这种**警示**
- 失败有 evidence（不是猜的）
- 用户曾纠正（"X 不能再做了"）

**反例**：
- "X 似乎有问题" → 证据不足，写 note 待观察
- "X 是 anti-pattern" → 走 ascended（有最优替代方案）

**模板**：

```org
* DONE <title>
:PROPERTIES:
:ID:       <timestamp>
:CREATED:  [<date>]
:CATEGORY: <category>
:TECH:     <tech>
:TYPE:     mistake
:ENTRY_TYPE: mistake
:WEIGHT:   1.0
:SOURCE_AGENT: hermes
:USAGE_COUNT: 0
:END:

* 错误
<做错了什么>

* 触发条件
<在什么场景下会犯>

* 为什么错
<根因>

* 修复 / 规避
<怎么避，下次怎么做>

* Evidence
<错误信息、命令输出、commit>
```

### ascended（多次失败后找到的正确做法）

**适用**：
- "经过 N 次试错，X 才是对的"
- 有**至少 2 次失败** + **1 次成功**的 evidence
- 是被验证过的方案，不是理论最优

**反例**：
- 第一次尝试成功 → 写 note，不写 ascended（没多次试错）
- "X 是 best practice" → 走 ascended 但需 evidence，否则写 note

**模板**：

```org
* DONE <title>
:PROPERTIES:
:ID:       <timestamp>
:CREATED:  [<date>]
:CATEGORY: <category>
:TECH:     <tech>
:TYPE:     ascended
:ENTRY_TYPE: ascended
:WEIGHT:   1.0
:SOURCE_AGENT: hermes
:USAGE_COUNT: 0
:END:

* 失败的尝试
<之前试过哪些方案，为什么失败>

* 最终方案
<为什么 X 是对的>

* 验证 evidence
<成功案例 + 复现步骤>

* 不适用场景
<哪些场景 X 不适用，防过度泛化>
```

## category / tech / type 字段

### category（业务分类）

**复用已有**（agenote_stats 现有 12 类）：

- guix / emacs / debug / general / kb / config / package / pi-extension / workflow

**新开 category**：必须经独立 review（用户拍板），不在本 skill 决定。

### tech（技术栈）

自由输入但优先复用已有。例如：guix, emacs, rust, TypeScript, hermes, ...

### type（卡片类型）

- workflow：工作流
- debug：调试
- knowledge：知识
- mistake：错误（与 entry=note 配）
- ascended：晋升（多次试错后的最优方案）
- feature：功能
- research：研究
- review：审查
- reference：参考
- config：配置

## 防 over-broad lesson（punkjazz.ai §05）

入 KB 前**主会话自查**：

- "这个 lesson 在另一个项目里也成立吗？"
  - 否 → local-only，不入 KB
  - 是 → 继续
- "这个 lesson 是不是只因我**这次**的代码特殊才成立？"
  - 是 → local-only
  - 否 → 继续
- "这个 lesson 已经被另一张 KB 卡片覆盖了吗？"
  - 是 → 不写重复卡，先 `agenote_search` 确认
- "我有**至少 1 个 evidence**（commit / 命令 / 文件路径）支撑这个 lesson 吗？"
  - 否 → 写 conversation，不写 KB
  - 是 → 入 KB

## 用户偏好 → 走 memory，不走 KB

KB 是**技术经验**。用户偏好走 `memory` tool：

- `target=user`：who the user is（name, role, preferences, style）
- `target=memory`：your notes（environment, conventions, tool quirks, lessons）

判断：

- "用户喜欢 X" → memory target=user
- "环境里 X 命令不存在" → memory target=memory
- "项目 Y 的部署拓扑是 Z" → fact_store (按需检索)
- "X 模式下应该用 Y pattern" → KB (agenote_add)

跨域一致性约束来自 MEMORY.md：

- markdown MEMORY.md / USER.md 只写跨所有仓库通用的规范与偏好
- 项目专属事实（部署拓扑、踩坑、环境细节、命令诀窍）一律 fact_store

## 真实案例样本

见 `references/example-funnel-run.md`。