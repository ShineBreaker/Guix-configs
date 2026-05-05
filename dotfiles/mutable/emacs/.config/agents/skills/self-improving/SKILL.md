---
name: self-improving
description: >
  跨会话持续改进 — 检测对话中的经验信号，触发知识库写入。
  Auto-detect: user corrections ("不对，应该是..."), non-obvious bugs,
  knowledge gaps, better approaches, environment-specific pitfalls.
  Triggers: "记录下来", "这个值得记住", "下次注意", "记一下",
  "写入记事本", "写入错题集", "save this", "record this",
  "值得写入知识库", "这个坑要记",
  "不对，应该是", "你搞错了", "用最有效的方法处理", "/ascended"
version: "2.0.0"
context: inline
user-invocable: true
allowed-tools:
  - Read
  - Bash(kb:*)
---

# Self-Improvement

在对话中自动检测经验信号，通过 `kb` CLI 将经验写入知识库，实现跨会话持续改进。

> CLI 操作细节和格式规范由 `knowledge-base` skill 定义。本 skill 仅关注 **何时/为何** 记录。

## 双输出原则

每次经验记录应产生两个结果：

1.  **经验卡片** — 完整的排查/发现过程（存储在 experiences/）
2.  **关联更新** — 检查并更新受影响的 pattern 或已有卡片

不产生关联更新时，至少确认「无关联 pattern 需更新」—— 不是跳过检查。

## 记忆职责边界

本 skill 的存储统一落到 `knowledge-base` 系统：

1.  `mistake` 语义 → 写成 `type: debug` 或 `config` 的经验卡片，`owner` 通常为 `collaborative`
2.  `note` 语义 → 写成 `type: workflow` / `research` / `config` 的经验卡片，或在重复出现后晋升为 pattern
3.  `memory cache` 语义 → 由 `patterns.org` 承担通用规则缓存，详细过程保留在经验卡片
4.  项目级/全局级 scope → 通过 `category`、`tech`、标题和正文边界表达

## 检测触发器

在对话中自动检测经验信号，触发记录。完整触发器列表见 `references/triggers.md`。

简表：

| 信号类型 | 推荐 type | 关键词/信号 |
| -------- | --------- | ----------- |
| 修正 | `debug` | "不对，应该是…"、"你搞错了…" |
| 知识空白 | `research` | 未知信息、过时文档、API 行为不符 |
| 非显而易见错误 | `debug` | 排查 >2 步、环境差异 |
| 更好方案 | `refactor` | 更优写法、更简路径 |
| 配置陷阱 | `config` | 跨工具集成踩坑、非默认组合 |

**注意防误触发**：用户描述报错但不纠正你、普通 review 无可复用经验、只要求继续下一步 → 不触发。

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
2.  **矛盾检测** — 检查新发现是否与已有卡片/pattern 矛盾
3.  **查看已有标签** — 运行 `kb fields` 查看现有 category/tech，优先复用已有标签
4.  **写入卡片** — 使用 `kb add`（CLI 用法见 `knowledge-base` skill）
5.  **校验格式** — 运行 `kb lint` 确保无 Markdown 残留
6.  **传播联动** — 检查是否有受影响的 pattern 或同类卡片需要更新
7.  **必要时晋升** — 同类经验达到阈值后写入 `kb patterns --add`
8.  **标注时效** — 对可能过时的结论标注验证日期和置信度

### `mistake` 卡片必须覆盖

写入纠错经验时，正文至少包含这些信息（用 Org 小节表达）：

1.  原始任务或问题
2.  用户纠错反馈链
3.  这次到底错在哪里
4.  最终正确处理
5.  下次开始前自检
6.  不确定结论标注置信度（`(推测)` / `(单源)`）
7.  可能过时的声明标注验证日期

### `note` 卡片必须覆盖

写入长期注意事项时，正文至少包含这些信息：

1.  事项内容
2.  为什么值得长期保留
3.  适用场景和边界
4.  后续行动或检查点
5.  不确定结论标注置信度和时效性

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

当同一问题被持续纠正 ≥2 次仍无法解决时，自动进入飞升模式。详细步骤和触发条件见 `references/ascended-mode.md`。

核心行为：输出固定句 → 全面检索所有知识源（`kb search` + `kb patterns --get`）→ 筛出最接近经验 → 解释前几轮失败原因 → 给出最强方案 → 写入/更新经验卡片。

## 最佳实践

1.  **即时记录** — 问题解决后立即写入，上下文最完整
2.  **标题要包含结论** — "Guix swap-space 需同时在 operating-system 声明" 优于 "swap 配置问题"
3.  **记录坑点而非过程** — 重点关注"没想到的地方"，而非逐步流水账
4.  **用 kb search 验证重复** — 写入前先搜一下，避免重复卡片
5.  **归纳通用模式** — 3 次同类经验后晋升为 pattern
