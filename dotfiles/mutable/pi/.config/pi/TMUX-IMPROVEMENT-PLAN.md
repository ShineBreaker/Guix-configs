# tmux-subagents 改进方案

基于当前 agent 体系改进（workfile 持久化、统一 handoff、新增 prompt 模板）对 tmux-subagents 扩展的适配改进。

## 当前代码分析

**扩展**：`extensions/tmux-subagents/index.ts`（862 行）
**Wrapper**：`~/.local/share/pi/scripts/subagent-wrapper.sh`（~280 行）

### 核心流程

```
subagent tool → discoverAgents() → launch*() → tmux split → wrapper.sh → pi --mode json → extract_result → waitForCompletion() → formatResults()
```

### 已有能力

- single / parallel / chain / list / status 五种模式
- 为每个 agent 注册 `/agentname` 快捷命令
- plan-review-gate（拦截 plannotator 提交，要求 planner 先审）
- agent frontmatter 解析（name/description/tools/model/thinking）
- wrapper 脚本解析 agent .md，传递系统提示和参数给 pi

---

## 改进项

### 改动 1：wrapper 执行完毕后自动将产出复制到 `.agent/workfile/`

**问题**：当前所有 agent 被要求将工作产物写入 `.agent/workfile/{agent}/`，但 agent 运行在独立的 pi 子进程中，其 CWD 可能不是项目根目录，且 wrapper 不知道项目根目录在哪里。

**方案**：在 wrapper 完成后，由 index.ts 的 `waitForCompletion()` 负责——检测 result.md 内容是否已经包含文件写入指令，如果不是，则由扩展本身负责将 result.md 复制到正确的 `.agent/workfile/` 路径。

具体实现：

1. `launchSingle()` / `launchParallel()` 新增参数接收项目 CWD
2. 在 `waitForCompletion()` 返回 RunResult 后，将 `result.md` 的内容写入 `{cwd}/.agent/workfile/{agent}/{date}-{summary}.md`
3. 文件名摘要从 task 文本提取（取前 30 字符 + hash 短串）
4. 自动创建 `.agent/workfile/{agent}/` 目录

**涉及文件**：index.ts

### 改动 2：chain 模式传递 workfile 路径信息

**问题**：chain 模式中 `{previous}` 只传递文本输出。但下游 agent 可能需要知道上游的 workfile 文件路径以便引用。

**方案**：在 `runChain()` 中，每步完成后将 workfile 路径注入到下一步的 task 文本中：

```
{previous}

---
上一步工作产物已持久化到: .agent/workfile/{agent}/{filename}
```

这样下游 agent 可以通过 `read` 读取完整文件而非依赖截断的 handoff 文本。

**涉及文件**：index.ts

### 改动 3：prompt 模板预注册为快捷命令

**问题**：当前只注册了 `/agentname` 快捷命令（单个 agent），但新加的 prompt 模板（parallel-research、research-and-implement）没有对应的快捷启动方式。主会话需要手写 JSON 才能调用。

**方案**：在扩展入口扫描 `prompts/` 目录下的 `.md` 文件，解析其中的 JSON 模板，注册为 `/prompt:{name}` 快捷命令。用户执行 `/prompt:parallel-research 调研 React vs Vue` 时自动填充模板并调用对应模式。

具体实现：

1. 新增 `discoverPrompts()` 函数，扫描 `{agentDir}/prompts/*.md`
2. 解析每个文件中的 JSON 块（chain / tasks / single），提取模式类型
3. 注册 `/prompt:{filenameWithoutExt}` 命令
4. 命令 handler 将用户参数替换 `{task}` 占位符后调用对应执行路径

**涉及文件**：index.ts

### 改动 4：`/agentname` 快捷命令结果也持久化到 workfile

**问题**：当前 `/agentname` 快捷命令的结果只通过 notify 展示，不经过 `waitForCompletion()` 的 result.md 流程。而 tool 调用的路径会生成 result.md。

**方案**：`/agentname` 命令的 handler 在 `waitForCompletion()` 返回后，也执行与改动 1 相同的持久化逻辑。

**涉及文件**：index.ts

### 改动 5：改进 agent list 输出格式

**问题**：当前 `action: "list"` 只输出 name + description，没有 tools、model 等信息。主会话在选择 agent 时缺乏足够信息。

**方案**：`action: "list"` 输出改为结构化表格，包含 tools、model、thinking 级别。

**涉及文件**：index.ts

### 改动 6：清理 plan-review-gate 中硬编码的提示文本

**问题**：plan-review-gate 的 block reason 文本是硬编码的中文提示，混在 TypeScript 代码中不好维护。

**方案**：将提示文本提取为顶部常量，保持代码整洁。这是纯代码卫生改动，不改行为。

**涉及文件**：index.ts

---

## 优先级

| 优先级 | 改动 | 理由 |
|--------|------|------|
| P0 | 改动 1：workfile 持久化 | 核心需求，所有 agent 改进的前提 |
| P0 | 改动 4：快捷命令也持久化 | 与改动 1 一致性 |
| P1 | 改动 2：chain 传递 workfile 路径 | 提升 chain 信息完整性 |
| P1 | 改动 3：prompt 模板快捷命令 | 让新 prompt 模板可被发现和使用 |
| P2 | 改动 5：改进 list 输出 | 改善体验 |
| P2 | 改动 6：提取硬编码文本 | 代码卫生 |

---

## 不做的改动

1. **不改 wrapper.sh**：wrapper 职责是启动 pi 子进程并收集结果，不应关心项目目录结构。持久化由 index.ts 在主进程中处理更可靠。
2. **不改 frontmatter 解析**：当前的 parseFrontmatter 逻辑已经满足需求（已支持 tools/model/thinking）。
3. **不改 tmux 分屏逻辑**：当前的分屏策略（上方新 pane / 右侧分割）运行良好。
