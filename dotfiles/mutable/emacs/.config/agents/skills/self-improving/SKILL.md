---
name: self-improving
description: 跨会话持续改进 — 检测对话中的经验信号，触发知识库写入
when_to_use: |
  Use when the conversation reveals experience worth recording.
  Auto-detect: user corrections, non-obvious bugs, knowledge gaps,
  better approaches discovered, environment-specific pitfalls.
  The model should proactively suggest recording when these signals appear.
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Bash(kb:*)
  - Bash(kb-lint:*)
  - Bash(kb\ add:*)
  - Bash(kb\ search:*)
  - Bash(kb\ tags:*)
  - Bash(kb\ patterns:*)
---

# Self-Improvement

在对话中自动检测经验信号，通过 `kb` CLI 将经验写入知识库，实现跨会话持续改进。

> CLI 操作细节和格式规范由 `knowledge-base` skill 定义。本 skill 仅关注 **何时/为何** 记录。

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

### 有价值的配置调整（→ type: config）

- 非默认的配置组合生效
- 跨工具集成（Emacs + Guix + Distrobox 等）的踩坑
- 系统级行为差异的发现

## 写入时机判断

### 必须写入

- 非显而易见的 bug 修复（排查 > 2 步）
- 涉及 Guix/Distrobox/Wayland/Emacs 等生态的特殊行为
- 配置调优过程中发现的坑
- 用户纠正了你的错误理解

### 不必写入

- 语法错误、拼写修正
- 文档已有明确答案的问题
- 一次性、无复用价值的操作
- 已有经验完全覆盖的情况

## 写入流程

检测到触发器后：

1. **检索重复** — 先 `kb search` 检查是否已有类似经验
2. **写入卡片** — 使用 `kb add`（CLI 用法见 `knowledge-base` skill）
3. **校验格式** — 运行 `kb-lint` 确保无 Markdown 残留

## 模式归纳（晋升机制）

当经验出现以下信号时，考虑从单张卡片归纳为通用模式：

### 晋升信号

- 同类经验出现 3 次以上（通过 `kb search` 检索验证）
- 跨不同文件/模块的相同根因
- 任何新会话都可能遇到的通用陷阱

### 归纳方式

```bash
kb patterns --add <<EOF
** 模式名称
   问题描述和通用解法。
   适用场景：...
   反例：...
EOF
```

### 晋升 vs 保留

- **晋升到 patterns.org**：跨项目通用规则、预防性指导
- **保留为经验卡片**：具体问题的完整排查过程（保留可追溯性）
- **两者共存**：晋升不删除原卡片，模式引用原卡片 ID

## 任务前经验检索

开始非平凡任务前，检索相关历史经验避免重复踩坑：

```bash
kb search "<任务关键词>"
kb tags emacs config
```

如果检索到相关经验，将其作为上下文参考，在回复中隐式应用。

## 最佳实践

1. **即时记录** — 问题解决后立即写入，上下文最完整
2. **标题要包含结论** — "Guix swap-space 需同时在 operating-system 声明" 优于 "swap 配置问题"
3. **记录坑点而非过程** — 重点关注"没想到的地方"，而非逐步流水账
4. **用 kb search 验证重复** — 写入前先搜一下，避免重复卡片
5. **归纳通用模式** — 3 次同类经验后晋升为 pattern
