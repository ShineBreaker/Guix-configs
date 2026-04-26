# Self-Improvement

通过 `kb` CLI 将错误、修正、经验教训写入知识库（`~/Documents/Org/experiences/`），实现跨会话持续改进。

与 `knowledge-base` skill 互补：本 skill 定义 **何时/为何** 记录，`knowledge-base` 定义 **如何** 操作 kb CLI。

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

## 写入时机

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

## 写入方式

检测到触发器后，使用 `kb add` 写入经验卡片：

```bash
kb add \
  --title "简明标题（问题 → 结论）" \
  --category <category> \
  --tech <tech> \
  --type <type> \
  --owner <owner> \
  --summary "一句话总结" \
  --stdin <<EOF
** 任务描述
发生了什么，期望什么

** 执行过程
1. 第一步尝试...
2. 发现...

** 难点与坑点
- 坑点 1：...

** 经验教训
- 核心结论

** 相关链接
- 参考文档/Issue/Commit
EOF
```

### 参数选择指南

**type**（记录类型）：

| type       | 使用场景                     |
| ---------- | ---------------------------- |
| `debug`    | 排错过程、错误修正、环境陷阱 |
| `config`   | 配置调整、系统集成、环境设置 |
| `feature`  | 新功能实现、工具链扩展       |
| `workflow` | 工作流优化、自动化、最佳实践 |
| `refactor` | 更优方案、代码改进、设计调整 |
| `research` | 知识空白填补、技术调研       |

**category**（技术领域）：

| category                                              | 覆盖范围                      |
| ----------------------------------------------------- | ----------------------------- |
| `emacs`                                               | Emacs 配置、Elisp、插件       |
| `nix`                                                 | Guix System、GuixSD、系统配置 |
| `general`                                             | 跨领域、通用经验              |
| `python` / `rust` / `go` / `scheme` / `shell` / `web` | 各语言生态                    |

**owner**（发现者）：

| owner           | 含义        |
| --------------- | ----------- |
| `ai`            | AI 自主发现 |
| `human`         | 用户指出    |
| `collaborative` | 协作发现    |

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
# 按任务关键词检索
kb search "<任务关键词>"

# 按技术栈检索
kb tags emacs config
```

如果检索到相关经验，将其作为上下文参考，在回复中隐式应用。

## 与 knowledge-base skill 的分工

| 维度     | self-improvement                      | knowledge-base      |
| -------- | ------------------------------------- | ------------------- |
| 核心职责 | **何时/为何**记录经验                 | **如何**操作 kb CLI |
| 触发时机 | 对话中自动检测                        | 用户显式要求        |
| 内容重点 | 检测触发器 + 晋升哲学                 | CLI 参数 + 工作流   |
| 依赖关系 | 调用 kb CLI（由 knowledge-base 定义） | 定义 kb CLI 用法    |

## 最佳实践

1. **即时记录** — 问题解决后立即写入，上下文最完整
2. **标题要包含结论** — "Guix swap-space 需同时在 operating-system 声明" 优于 "swap 配置问题"
3. **记录坑点而非过程** — 重点关注"没想到的地方"，而非逐步流水账
4. **用 kb search 验证重复** — 写入前先搜一下，避免重复卡片
5. **归纳通用模式** — 3 次同类经验后晋升为 pattern
6. **写入后校验格式** — 运行 `kb-lint` 检查 Markdown 残留，用 `kb-lint --fix` 自动修复

## Org 格式规范（CRITICAL）

卡片格式为 **Org mode**，写入 `kb add --stdin` 内容时禁止使用 Markdown 语法：

- 代码块用 `#+begin_src lang ... #+end_src`，禁止 ` ```lang ``` `
- 粗体用 `*text*`，禁止 `**text**`
- 子标题用 `*** heading`，禁止 `## heading`
- 详细规范见 knowledge-base skill 的"格式规范"章节
