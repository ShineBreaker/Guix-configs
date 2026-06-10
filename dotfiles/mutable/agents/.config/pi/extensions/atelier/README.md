## Subagent 架构

> **实现位置**：subagent 工具、`/<agent-name>` 快捷命令、plan-review-gate、worker/planner 上下文注入均由本地扩展 `extensions/atelier/` 实现。
> 源码：`extensions/atelier/{index,launcher,runner,config,discovery,context}.ts` + 辅助脚本 `~/.local/share/pi/scripts/subagent-wrapper.sh`。
> 模型路由通过 `settings.json` 的 `atelier.tiers` 配置 + agent frontmatter `tier:` 字段驱动；不要直接修改 `subagent-wrapper.sh` 试图改模型选择逻辑——所有 model 解析都在 `extensions/atelier/runner.ts` 的 `resolveModelChain()` 里。

### 设计原则

1. **规划者拥有 scope 并发布任务，不做编码**：写计划、读 handoff、决定下一步是规划者的工作。编辑文件、运行 git merge、内联修复冲突不是。
2. **规划者不知道谁接了任务**：脚本将每个任务路由到一个 agent。规划者的心智模型保持在任务层面。
3. **Worker 完全隔离**：一个任务、一个 repo 克隆、不与任何其他 agent 通信。完成时一个 handoff。
4. **通过 handoff 持续推进**：规划者收到迟到的 handoff 后可以重新规划。直到规划者决定停止发布才结束。
5. **传播而非同步**：兄弟之间不互通、层级之间不共享状态。每层只看到其子节点的 handoff。

### 节点类型

| 节点           | 运行循环？ | Scope                  | 输出                            |
| -------------- | ---------- | ---------------------- | ------------------------------- |
| Planner        | 是         | 整个用户目标           | 用户面向消息                    |
| Subplanner (↻) | 是         | 父 scope 的一个切片    | Handoff 给父节点                |
| Worker         | 否         | 一个具体任务           | Handoff 给发布它的 planner      |
| Verifier       | 否         | 一个目标任务的验收标准 | 判定 handoff 给发布它的 planner |

### Verification 级别

| 级别                 | 含义                        | 规划者响应           |
| -------------------- | --------------------------- | -------------------- |
| `live-ui-verified`   | 实际复现 bug 并确认修复消除 | 信任为已发布         |
| `unit-test-verified` | 目标测试覆盖变更路径并通过  | 非 UI bug 可接受     |
| `type-check-only`    | 仅类型检查/构建通过         | 弱，仅适合纯类型变更 |
| `verifier-blocked`   | 环境故障阻止验证            | 不算已验证，需重跑   |
| `verifier-failed`    | 验证运行但修复无效          | 需要后续修复任务     |

### 失败恢复策略

| 失败模式          | 策略                                                   |
| ----------------- | ------------------------------------------------------ |
| `cap-hit` / `oom` | 缩小范围重试：拆分更窄的任务、更紧的路径、更精简的目标 |
| `network-drop`    | 原样重试，视为瞬时故障                                 |
| `tool-error`      | 换模型重试                                             |
| `unknown`         | 原样重试一次，再失败则放弃                             |

同一任务重试 2 次后，优先放弃而不是第 3 次尝试，除非有具体证据表明下次会成功。

### 执行管线

subagent 执行分为三层：

1. **Pi 主会话** → 调用 `subagent` 工具（由 `atelier` 扩展注册）
2. **atelier 扩展** → 解析参数、发现 agent、创建 tmux 分屏、启动 wrapper
3. **subagent-wrapper.sh** → 解析 agent frontmatter、构造 `pi --mode json` 命令、管道到 `extract-pi-result.py`

```
主会话 → subagent tool
         ↓
    discoverAgents()    扫描 agents/*.md，解析 frontmatter
         ↓
    launchSingle/Parallel/Chain()   创建 runDir、status.json、分屏启动
         ↓
    subagent-wrapper.sh   (tmux 窗格内)
      ├─ parse_agent_md     提取 model/thinking/tools + system prompt body
      ├─ pi --mode json     运行独立 Pi 实例
      └─ extract-pi-result.py   解析 JSON 流，提取最终 assistant 文本
         ↓
    waitForCompletion()   轮询 status.json，超时/退出检测
```

### Chain 模板变量

prompt 模板（`prompts/*.md`）中嵌入的 JSON chain 支持：

- `{task}` — 用户输入的根任务（`params.task`）
- `{previous}` — 上一步 agent 的输出文本（pipeline 串联）

### Agent 快捷命令

atelier 扩展会为每个 agent 自动注册 `/<agent-name>` 命令（如 `/scout`、`/worker`），直接启动 single 模式 subagent。

### Plan Review Gate

`plan-review-gate.ts` 通过 Pi 的 `tool_call` 事件拦截 `plannotator_submit_plan`：

1. 首次提交 → block，reason 指示 LLM 调用 planner subagent 审查
2. 审查后再次提交 → 放行（`reviewedPlans` Set 避免循环）

**前提**：plannotator 已安装且 planning phase 启用了 `subagent` 工具（见 `plannotator.json`）。

### Visual Agent 自动移交

当用户输入包含图片但当前模型不支持视觉时，`before_agent_start` hook 自动触发：

1. 检测 `event.images` 是否存在 + `ctx.model.input` 是否包含 `"image"`
2. 不支持视觉时：将 base64 图片写入 `/tmp/pi-visual/` 临时文件
3. 在系统提示中追加指示，要求 LLM 调用 `subagent(agent: "visual", images: [...])`
4. visual agent 使用 `zai/GLM-5V-Turbo` 视觉模型，通过 `@file` 语法接收图片

**递归防护**：wrapper 导出 `PI_SUBAGENT=1` 环境变量，hook 检测到后跳过。

### Worker / Planner 上下文动态注入

atelier 的 `before_agent_start` hook 根据 plannotator plan mode 状态决定主会话的 role context：

1. **plan mode 检测**（双保险）：
   - 主路径：读 `ctx.sessionManager.getEntries()` 找最近的 `custom` 条目（`customType === "plannotator"`），检查 `data.phase === "planning"`
   - 兜底：扫描 `event.systemPrompt` 是否含 `[PLANNOTATOR - PLANNING PHASE]` 标记
   - 两者都为否则默认走 worker 上下文
2. **按模式注入**：
   - plan mode → 读 `agents/planner.md` → 剥除 subagent-only 段 → 追加到 systemPrompt
   - 默认 → 读 `agents/worker.md` → 剥除 subagent-only 段 → 追加到 systemPrompt
3. **plan mode 优先级提示**：plan mode 下额外追加提示，告诉 LLM plannotator 注入的 `[PLANNOTATOR - PLANNING PHASE]` 段中的约束（写仅限 .md in cwd、不修改代码、iterative planning workflow）优先级最高

**一文件两用机制**：`agents/worker.md` 和 `agents/planner.md` 是主会话和 subagent 共享的 prompt 源。文件内用 HTML 注释 `<!-- @atelier:subagent -->...<!-- /@atelier:subagent -->` 切出 subagent-only 段（workfile 路径、详细输出模板等）：

- 主会话注入 → atelier 调用 `stripSubagentOnlySection()` 剥除这些段
- subagent 启动 → atelier 预先生成 `runDir/subagent-prompt.md`（剥除 HTML 注释标记但保留内容），wrapper 通过 `--prompt-file` 读取

源码：`extensions/atelier/context.ts`（切片工具）、`extensions/atelier/index.ts` 的 "Worker / Planner 上下文注入" 块、`extensions/atelier/launcher.ts` 的 `prepareAgentPrompt()`。
