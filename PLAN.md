# Loop/Graph Engineering 方法论落地：对抗性评估与实施方案

## Context

三篇文章（Graph Engineering / Loop Engineering / From Loop to Graph）提出了 agent 系统的硬性方法论。另一个 Agent 的总结（下称"Summary"）声称系统已实现 70%，并给出了 G1-G11 的缺口列表。

**本文的目的**：对 Summary 进行对抗性质疑，基于实际代码审计提出更准确的评估和更务实的方案。

---

## §1 对 Summary 的对抗性质疑

### 1.1 "70% 已实现"是严重高估

Summary 把"工具存在"等同于"方法论已实现"。实际代码审计揭示：

| 组件 | Summary 声称 | 实际情况 |
|------|-------------|---------|
| completion-gate | "MAX_REENTRY=2 防 agent 撒谎" | `isTaskToolAvailable()` **硬编码返回 false** → gate 永远 no-op |
| workflow | "chain / parallel 两种 mode" | 只有线性 chain + 简单 parallel，**无任何拓扑边** |
| authority gate | "bash-gate / edit-gate 已实现" | 只保护 **Crush**，Pi 主会话完全裸奔 |
| Plan Review Gate | 未提及 | **已存在**于 atelier index.ts，拦截 plannotator_submit_plan 强制 oracle 审查 |
| H3 (consequential decision) | "🔴 缺失" | **事实错误**——Plan Review Gate 就是 H3 的实现 |

**真实完成度：~40%**。骨架在，但关键肌肉（验证闭环、authority 硬约束、completion 反证）是断的。

### 1.2 G1 (worktree) 作为 P0 是错误的优先级判断

Summary 把 Hermes 文中"多 agent 并发写同一 repo"的问题直接移植到本系统。但：

- 这是**单用户个人系统**，不是多租户 SaaS
- atelier subagent 各自在独立 tmux pane 运行，操作的是**同一个工作目录**但任务语义不同（scout 只读、worker 写代码、reviewer 只读）
- 实际观测到的痛点不是"两个 worker 互相覆盖"，而是"完成声明无人验证"

**Worktree 隔离是 P2，不是 P0。** 只有当用户真正开始让多个 worker 并发修改同一 repo 的不同文件时才有意义。

### 1.3 G6 (graph topology) 作为"最核心论点"是本末倒置

Summary 说"这是文章最核心论点的物理实现"。**错。** 三篇文章最核心的论点是：

> "The durable axis was never loops versus graphs. It is **ungrounded versus grounded**."

没有 anchors 的图 = 精致互证网络 = 一切自洽无物被验证。**先建 grounding，再建 topology。** Summary 把末篇的警示（"graphs fail too, circularly"）当成了建设目标。

### 1.4 Summary 遗漏了系统中最重要的已有实现

**Plan Review Gate**（atelier index.ts 第 56-64 行）：

```typescript
const PLAN_REVIEW_GATE_PROMPT = [
  "任务提交前需要先让 oracle 审查计划。",
  "请调用 subagent 工具：",
  'subagent(agent: "oracle", task: "审查以下实施计划的架构合理性和风险...")',
  ...
].join("\n");
```

这已经是：
- H3（consequential decision 前独立对比）✅
- H4 的雏形（独立 reviewer 攻击）🟡
- Loop Eng "independence" 原则的实例化 ✅

Summary 完全没看到这个。这说明它没有真正读代码。

---

## §2 方法论提炼：真正可操作的硬性原则

从三篇文章中提炼出对**本系统**真正有意义的原则（按实际价值排序）：

### P1: 完成声明必须被独立反证（H4）
> "When an agent says the work is finished, give the result to a fresh reviewer whose job is to disprove that claim."

**当前状态**：completion-gate 是 no-op。Plan Review Gate 只拦截 plan 提交，不拦截 task 完成。

### P2: Authority 必须是机制而非规约（H6/H10）
> "Protected actions require approval from outside the agent process."

**当前状态**：AGENTS.md 写"禁止 AI agent 自行运行 blue rebuild"——这是规约。Crush 有 bash-gate 硬拦截——但 Pi 没有。

### P3: 每个任务必须声明"什么算误导性成功"（H1）
> "Every meaningful task begins by stating what would count as a misleading success."

**当前状态**：loopctl task.md 是自由文本，无结构化 schema。atelier task 是纯字符串。

### P4: Verifier 必须独立于 worker 的 framing（H9）
> "A verdict from something that shares your assumptions is theater dressed as verification."

**当前状态**：atelier tier 系统提供了模型多样性的基础设施（ultra/pro/quick/visual 用不同模型），但没有被用于"reviewer 必须用不同模型"的约束。

### P5: 教训进入持久判断前必须被审查（Graph Eng §05）
> "Independent review helps prevent an isolated mistake from turning into a permanent rule."

**当前状态**：agenote 的 distill 必须人工 review 才进 skills/ ✅。这是**已经正确实现的 anchor**。

### P6: 必须有不可调的冻结规则（H10）
> "Some nodes must be frozen — rules the optimizing loops are never allowed to tune."

**当前状态**：edit-gate.sh 禁止 tmp/、channel.lock、~/.config —— 但只保护 Crush。且这些规则散落在脚本里，没有统一声明。

---

## §3 实施方案：激活休眠基建 > 新建基建

核心策略：**不造新轮子，把已有的轮子接上电。**

### Phase 1: Pi Authority Gate（1-2 天，最高优先级）

**问题**：Pi 主会话可以执行 `blue rebuild`、`guix system reconfigure`、直接写 `~/.config/` 等危险操作。AGENTS.md 的规约层禁止在 LLM 不遵守时毫无作用。

**方案**：创建 Pi 扩展 `pi-gate`，复用 Crush bash-gate/edit-gate 的逻辑。

**实现路径**：
- 在 `dotfiles/mutable/pi/.config/pi/extensions/pi-gate/index.ts` 创建扩展
- 使用 Pi 的 `tool_call` hook（进程内 async fn，可 mutate event.input，返回 `{ block: true, reason }` 拦截）
- **注意**：Pi 的 `tool_call` 是 in-process 协议，不能 spawn bash-gate.sh 子进程。必须用 TypeScript 复刻 bash-gate.sh 的判定逻辑
- 拦截 `bash` 工具调用：TypeScript 复刻 Phase 1 (block) + Phase 2 (auto-approve) 逻辑
- 拦截 `edit`/`write` 工具调用：TypeScript 复刻 protected paths + 敏感信息检测
- 额外增加：`blue rebuild`、`guix system reconfigure`、`guix home reconfigure` 的硬拦截
- 从 `anchors.json`（Phase 4）读取 frozen_commands / frozen_paths，实现单一权威源

**关键文件**：
- 新建：`dotfiles/mutable/pi/.config/pi/extensions/pi-gate/index.ts`
- 参考：`dotfiles/immutable/agents/.config/crush/hooks/bash-gate.sh`
- 参考：`dotfiles/immutable/agents/.config/crush/hooks/edit-gate.sh`
- 参考：`dotfiles/mutable/pi/.config/pi/extensions/global-context/index.ts`（hook 注册模式）

**验证**：在 Pi 会话中尝试 `blue rebuild` → 应被拦截并提示"请用户手动执行"。

### Phase 2: 激活 Completion Gate（2-3 天）

**问题**：subagent 声称完成时无人验证。completion-gate 因 `isTaskToolAvailable()=false` 永远 no-op。

**方案**：两步走——

**2a. 连接 todo 工具**：settings.json 已安装 `@juicesharp/rpiv-todo`。修改 completion-gate 的 `isTaskToolAvailable()` 检测逻辑，使其在 todo 工具可用时返回 true。这样 worker 如果创建了 task 但没完成，gate 会触发 reentry。

**2b. 扩展 Plan Review Gate 到 completion 路径**：在 atelier 的 `waitForCompletion` 返回后、格式化结果前，对 worker 类 agent 的完成声明触发一次 adversarial check：
- 用不同 tier 的模型（如 worker 用 pro，reviewer 用 quick 或 ultra）
- 给 reviewer 的 prompt 只包含：task 描述 + worker 的 return header + git diff
- **不给** worker 的完整对话历史（保证 framing 独立性）
- reviewer 输出 verdict: pass / fail + 攻击点列表
- fail → 自动 reentry（受 MAX_REENTRY=2 限制）
- **循环依赖终止**：reviewer 属于 READ_ONLY_AGENTS 白名单（scout/oracle/reviewer/visual），永远不触发 completion-gate，避免"reviewer 的完成谁来 review"的无限递归

**关键文件**：
- 修改：`dotfiles/mutable/pi/.config/pi/extensions/atelier/registry/completion-gate.ts`
- 修改：`dotfiles/mutable/pi/.config/pi/extensions/atelier/index.ts`（completion 后触发 review）
- 参考：Plan Review Gate 已有模式（同文件第 56-64 行）

**验证**：启动一个 worker 完成一个简单任务 → 观察是否自动触发 reviewer pane → reviewer 输出 verdict。

### Phase 3: 任务 Schema 结构化（1-2 天）

**问题**：task 是纯字符串，没有"什么算误导性成功"的结构化声明。

**方案**：在 loopctl 的 task.md.tmpl 和 atelier 的 task 传递中增加 frontmatter：

```yaml
---
false_success_conditions:
  - "报告说完成了但没有实际修改文件"
  - "测试通过但测试标准在过程中被降低了"
acceptance_criteria:
  - "运行 `blue check` 无错误"
  - "git diff 显示预期的文件变更"
verification_command: "blue --dry-run home"
---
```

atelier 在构造 reviewer prompt 时自动注入这些条件，让 reviewer 知道"攻击什么"。

**⚠ 3 处耦合**（oracle 审查发现）：task.md 传递链有 3 处串联写入，frontmatter 解析必须同步处理：
1. `launcher.ts:168-176` prepareRunDir 直接 writeFileSync(task)，需增加 frontmatter 解析
2. `subagent-wrapper.sh:200,243` 把 task.md 整个内容当 prompt 喂给 pi，需剥离 frontmatter 只传 body
3. `loop_lib/state.sh:37-81` 用 awk 拼接 JSON，frontmatter 的 `:` 会破坏 state.json——需在写入前剥离

**关键文件**：
- 修改：`~/.local/bin/loop_lib/templates/task.md.tmpl`
- 修改：`dotfiles/mutable/pi/.config/pi/extensions/atelier/runtime/launcher.ts`（prepareRunDir 时解析 frontmatter）
- 新建：`.agents/templates/task-schema.md`（schema 文档）

### Phase 4: Frozen Rules 统一声明（0.5 天）

**问题**：冻结规则散落在 bash-gate.sh、edit-gate.sh、AGENTS.md 中，没有单一权威源。

**方案**：创建 `dotfiles/immutable/agents/.config/agents/anchors.json`：

```json
{
  "frozen_paths": ["tmp/", "channel.lock", "~/.config/", "~/.local/"],
  "frozen_commands": ["blue rebuild", "guix system reconfigure", "guix home reconfigure"],
  "human_only_actions": ["distill → skills/", "channel.lock 更新", "系统级 reconfigure"],
  "anchor_measurements": [
    "blue check 退出码 = 0",
    "git diff 非空（有实际变更）",
    "测试套件实际执行（不是被跳过）"
  ]
}
```

pi-gate 扩展和 completion reviewer 都从这个文件读取规则。修改此文件本身需要人工操作（meta-frozen）。

### Phase 5: Output 完整落盘（0.5 天，loopctl 专属）

**问题**：loopctl state.json 只保存 output tail 200 字符，违反 H8（audit trail）。

**方案**：每轮 iteration 落盘 `${session_dir}/iter-NNN.full.txt`，state.json 存 ref 路径。

**关键文件**：
- 修改：`~/.local/bin/loop_lib/agent.sh`（输出提取后写完整文件）
- 修改：`~/.local/bin/loop_lib/state.sh`（state.json 增加 `output_file` 字段）

---

## §4 明确不做的事（对抗 Summary 的过度工程）

| Summary 建议 | 我的判断 | 理由 |
|-------------|---------|------|
| G1 worktree 隔离 (P0) | **降级到 P3+** | 单用户系统，并发写冲突是理论问题不是观测到的痛点 |
| G6 graph topology (P2) | **推迟到有实际需求** | 没有 grounding 的 topology = 精致互证网络。先 Phase 1-4 |
| G10 paired metrics | **不做** | 本系统不优化单一 metric，不存在 Goodhart 风险 |
| G11 audit loop | **agenote curate 已覆盖** | 周期性 `agenote curate` 就是 measurement decay 的 audit loop |
| 新建 hermes-architecture.md | **不做** | 文档不是方法论落地的瓶颈 |

---

## §5 实施顺序与依赖

```
Phase 1 (pi-gate)          ← 无依赖，立即开始，1-2 天
    ↓
Phase 2 (completion gate)  ← 依赖 Phase 1（reviewer 的命令也需要 gate 保护）
    ↓
Phase 3 (task schema)      ← 依赖 Phase 2（reviewer 需要知道攻击什么）
    ↓
Phase 4 (anchors.json)     ← 可与 Phase 3 并行
    ↓
Phase 5 (output 落盘)      ← 独立，任何时候可做
```

---

## §6 Verification

| Phase | 验证方法 |
|-------|---------|
| 1 | Pi 会话中执行 `blue rebuild` → 被拦截；执行 `ls` → 放行；写 `tmp/foo` → 被拦截 |
| 2 | `subagent(agent:"worker", task:"...")` 完成后自动弹出 reviewer pane；reviewer 用不同 tier |
| 3 | loopctl start 时 task.md 包含 frontmatter；atelier task 解析出 false_success_conditions |
| 4 | pi-gate 和 reviewer 都读 anchors.json；修改 anchors.json 需要人工 |
| 5 | loopctl 运行 2 轮后，iter-001.full.txt 和 iter-002.full.txt 存在且内容完整 |

---

## §7 与 Summary 的核心分歧总结

| 维度 | Summary | 我的判断 |
|------|---------|---------|
| 完成度 | 70% | ~40%（骨架在，肌肉断） |
| P0 | worktree 隔离 | **authority gate**（风险最高、effort 最低） |
| 核心建设 | graph topology | **grounding**（先触地，再组网） |
| 实施策略 | 新建基建 | **激活休眠基建**（completion-gate、Plan Review Gate、tier 系统） |
| H3 状态 | 🔴 缺失 | ✅ 已有（Plan Review Gate） |
| 最大风险 | 多 worker 冲突 | **完成声明无人验证**（Graph Eng §04 的 4 bug 案例） |

---

## §8 用户确认的决策

| 决策点 | 选择 | 理由 |
|--------|------|------|
| 优先级排序 | gate > review > worktree | 单用户系统，authority 裸奔是实际风险，worktree 是理论问题 |
| Reviewer 模型独立性 | 不同 tier（同 provider 不同模型） | 复用已有 tier 系统，零额外配置，模型差异足够保证 framing 独立 |
| Gate 拦截策略 | 硬拦截 + 提示（与 Crush bash-gate 一致） | 简单直接，LLM 无法绕过，stderr 输出原因供重新决策 |
