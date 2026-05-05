---
name: self-improving
description: 跨会话持续改进 — 检测对话中的经验信号，触发知识库写入
version: "2.0.0"
when_to_use: |
  Use when the conversation reveals experience worth recording.
  Auto-detect: user corrections ("不对，应该是..."), non-obvious bugs,
               knowledge gaps, better approaches discovered, environment-specific pitfalls.
  Triggers: "记录下来", "这个值得记住", "下次注意", "记一下",
            "写入记事本", "写入错题集", "save this", "record this",
            "值得写入知识库", "这个坑要记",
            "不对，应该是", "你搞错了", "用最有效的方法处理", "/ascended"
  The model should proactively suggest recording when these signals appear.
context: inline
user-invocable: true
allowed-tools:
  - Read
  - Bash(kb:*)
---

# Self-Improvement

在对话中自动检测经验信号，通过 `kb` CLI 将经验写入知识库，实现跨会话持续改进。

> CLI 操作细节和格式规范由 `knowledge-base` skill 定义。本 skill 仅关注 **何时/为何** 记录。

## 记忆职责边界

本 skill 的存储统一落到 `knowledge-base` 系统：

1.  `mistake` 语义 → 写成 `type: debug` 或 `config` 的经验卡片，`owner` 通常为 `collaborative`
2.  `note` 语义 → 写成 `type: workflow` / `research` / `config` 的经验卡片，或在重复出现后晋升为 pattern
3.  `memory cache` 语义 → 由 `patterns.org` 承担通用规则缓存，详细过程保留在经验卡片
4.  项目级/全局级 scope → 通过 `category`、`tech`、标题和正文边界表达

## 检测触发器

在对话中自动检测以下信号，触发经验记录：

### 修正（→ type: debug, owner: collaborative）

- "不对，应该是..."
- "Actually, it should be..."
- "你搞错了..."
- "That's wrong..."

### 知识空白（→ type: research）

- 用户提供你不知道的信息
- 你引用的文档已过时
- API 行为与你的理解不符

### 非显而易见的错误（→ type: debug）

- 命令返回非零退出码
- 排查超过 2 步才定位根因
- 涉及环境差异（Guix/Distrobox/Wayland 等）

### 更好的方案（→ type: refactor）

- 发现比初始实现更优的写法
- 用户指出了更简洁的解决路径
- 事后意识到应该用不同工具/方法

### 配置调整陷阱（→ type: config）

- 非默认的配置组合生效
- 跨工具集成（Emacs + Guix + Distrobox 等）的踩坑
- 系统级行为差异的发现

### 触发器列表（综合自 Mistakebook）

#### 错题集触发

- "你这里错了"、"这不对"、"你又犯同样的错"
- "重新改"、"按我说的改"、"我来纠正你"
- "还没改对"、"你没有吃透"、"你理解反了"
- "这个回答有问题"、"这个地方你改坏了"
- "你把之前的要求漏掉了"、"还是有问题"
- 用户明确指出你的回答错误（即便语气温和）

#### 记事本触发

- "写入记事本"、"记一下这个事项"
- "这个不是错题，但要记住"
- "把这个注意事项记下来"、"这个以后都要注意"
- "把这条规则记到记事本"、"这个结论值得长期保留"

#### 飞升模式触发

- 同一案例被否定两次以上
- "用最有效的方法处理"、"use the most effective method"
- "你需要根据你见过最有效的方法来处理这个问题"
- `/ascended`

### 不应误触发

- 用户只是描述程序报错，但没有纠正你，也没有要求长期记录
- 用户在普通 review 中指出代码风险，但没有形成可复用经验
- 用户只是要求继续下一步，而不是回头纠正或归档
- 用户引用别人的批评原文，不是在纠正当前回答

## 运行时闭环

遇到纠错或记事信号后，在当前会话内维护一个轻量 case：

1.  `entry_type`：`mistake` 或 `note`
2.  `original_prompt` / `original_reply`
3.  `feedback_chain`：用户的纠错或补充链
4.  `latest_fixed_reply`
5.  `rejection_count` / `correction_attempt_count`
6.  `knowledge_sources_reviewed`
7.  `archive_status`：`candidate`、`confirmed`、`written`

归档规则：

1.  先解决当前问题，再写入知识库；不要为了归档打断修复
2.  写入前先 `kb search` 去重
3.  对 `mistake`，必须记录「错在哪里」「以后如何避免」「最终正确处理」
4.  对 `note`，必须记录「为什么值得长期保留」「适用边界」
5.  用户仍在纠正时，合并到同一个 case，不要新建多张重复卡片

如果上下文压缩风险明显，且路径可用，可以把 case 摘要 checkpoint 到 `~/.mistakebook/runtime-journal.md`；这只是会话状态备份，不是最终知识库存储。

## 写入时机判断

### 必须写入

- 非显而易见的 bug 修复（排查 \> 2 步）
- 涉及 Guix/Distrobox/Wayland/Emacs 等生态的特殊行为
- 配置调优过程中发现的坑
- 用户纠正了你的错误理解

### 不必写入

- 语法错误、拼写修正
- 文档已有明确答案的问题
- 一次性、无复用价值的操作
- 已有经验完全覆盖的情况
- 当前问题尚未解决，用户仍在纠正

## 写入流程

检测到触发器后：

1.  **检索重复** — 先 `kb search` 检查是否已有类似经验
2.  **查看已有标签** — 运行 `kb fields` 查看现有 category/tech，优先复用已有标签
3.  **写入卡片** — 使用 `kb add`（CLI 用法见 `knowledge-base` skill）
4.  **校验格式** — 运行 `kb lint` 确保无 Markdown 残留
5.  **必要时晋升** — 同类经验达到阈值后写入 `kb patterns --add`

### `mistake` 卡片必须覆盖

写入纠错经验时，正文至少包含这些信息（用 Org 小节表达）：

1.  原始任务或问题
2.  用户纠错反馈链
3.  这次到底错在哪里
4.  最终正确处理
5.  下次开始前自检

### `note` 卡片必须覆盖

写入长期注意事项时，正文至少包含这些信息：

1.  事项内容
2.  为什么值得长期保留
3.  适用场景和边界
4.  后续行动或检查点

## 模式归纳（晋升机制）

当经验出现以下信号时，考虑从单张卡片归纳为通用模式：

### 晋升信号

- 同类经验出现 3 次以上（通过 `kb search` 检索验证）
- 跨不同文件/模块的相同根因
- 任何新会话都可能遇到的通用陷阱

### 模式写作规范

模式 = 从多次经验中抽象出的紧凑规则，非排查叙事。**声明式事实，一句话结论先行。**

    ✅ "Guix 系统重配置后若 swap 不生效，需同时检查 operating-system 声明和 fstab"
    ❌ "有一次配置 swap 时发现没生效，排查了很久，最后发现是..."
    ❌ "Always declare swap in operating-system"（指令式）

结构（每条 ≤5 行）：

    ** <结论性标题>               ← 一眼能看出规则
       <一句话描述问题和通用解法>。 ← 声明式，非指令
       适用：<场景>
       例外：<反例或边界条件>
       参考：<引用经验卡片 ID>

### 归纳方式

```bash
kb patterns --add <<'EOF'
** Guix swap-space 需同时在 operating-system 声明
   swap-space 配置后若重启不生效，需检查 operating-system 中是否有
   swap-devices 声明——仅 fstab 不够。
   适用：Guix 系统重配置后 swap 异常
   例外：临时 swap 文件无需此声明
   参考：20260423-230246
EOF
```

### 晋升 vs 保留

- **晋升到 patterns.org**：跨项目通用规则、预防性指导
- **保留为经验卡片**：具体问题的完整排查过程（保留可追溯性）
- **两者共存**：晋升不删除原卡片，模式引用原卡片 ID

### 模式即时修补

从知识库检索到模式（patterns.org）并使用后，如果发现该模式已过时、不完整或有误，必须立即修补——不要等待用户提醒。无人维护的模式是负担，不是资产。

修补信号：

- 模式描述的解法对新版本不再适用
- 模式缺少关键的边界条件或反例
- 模式的前提条件已发生变化
- 有新的经验卡片可以补充到模式的引用中

修补方式：

```bash
# 直接编辑 patterns.org，修正有问题的模式条目
# 修补后运行 lint 确保格式正确
kb lint --fix
```

## 飞升模式（Ascended Mode）

当同一问题被用户持续纠正（≥2 次）仍无法解决时，自动进入飞升模式——全面检索所有知识源后给出最强方案。

### 触发条件

满足任一即触发：

1.  `rejection_count >= 2`（同一案例被明确否定两次以上）
2.  已进入 follow-up 纠错但明显原地打转
3.  问题复杂到必须全量检索历史经验

### 手动触发

用户说「用最有效的方法处理这个」或输入 `/ascended` 时立即进入。

### 执行步骤

进入飞升模式后：

1.  输出固定句：`我现在会根据我见过最有效的方法来处理这个问题，我将检索我的所有知识库。`
2.  明确问题核心冲突点
3.  `kb search <关键词>` 全面检索相关经验卡片
4.  `kb tags <相关标签>` 和 `kb patterns --get` 检索相关模式
5.  核对当前仓库真实文件、真实输出、真实文档
6.  对照当前问题，筛出最接近的既有经验
7.  解释为什么前面几轮仍失败
8.  选定最强方案重新处理
9.  解决后写入或更新经验卡片，并在必要时修补 pattern

飞升模式不是语气更强，而是处理方式升级：多轮检索 → 多轮比对 → 多轮校正 → 最有效方案。

### 任务前 Scholar Preflight

开始非平凡任务前，如果当前不在纠错循环或飞升模式中，执行轻量级预检：

```bash
kb search "<当前任务关键词>"
```

如果返回高相关经验：

- 在回复前输出历史提醒：「我看到这个任务和你之前遇到的问题有关，我会注意...」
- 将相关经验作为上下文参考

如果返回空或低相关：沉默，不主动展示检索结果。

### 状态持久化

在长时间对话中，若检测到上下文压缩风险，先将当前案例状态 checkpoint 到 `~/.mistakebook/runtime-journal.md`（如果该路径可用）。确保纠错循环不会因上下文丢失而中断。

## 最佳实践

1.  **即时记录** — 问题解决后立即写入，上下文最完整
2.  **标题要包含结论** — "Guix swap-space 需同时在 operating-system 声明" 优于 "swap 配置问题"
3.  **记录坑点而非过程** — 重点关注"没想到的地方"，而非逐步流水账
4.  **用 kb search 验证重复** — 写入前先搜一下，避免重复卡片
5.  **归纳通用模式** — 3 次同类经验后晋升为 pattern
