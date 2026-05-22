# Pi Agent 配置 - 审查报告

## 审查信息

- **审查日期**: 2026-05-22
- **审查范围**: `.config/pi/extensions/{tmux-subagents,global-context}/index.ts`、`.local/bin/{pi,pi-update,pi-acp}`、`.local/share/pi/scripts/*`，并核对 `settings.json`、agent frontmatter、prompt 模板和当前 stow 后运行态
- **项目类型**: Pi / TypeScript extension / Bash wrapper / Python JSON stream helper

## 评分

- **总分**: 4 / 10
- **同类项目水平**: 中低

## 门控判定

**FAIL**

核心 subagent 执行器存在权限约束失效、声明协议不匹配、无限等待和失败误报问题；这些不是风格问题，会直接破坏 agent 编排的可靠性。

## 审查详情

### 1. 架构设计

#### ✅ 优点

- `.config/pi/settings.json:46` 与 `.config/pi/settings.json:51` 将两个本地 extension 的配置集中在核心 settings 中，`.config/pi/AGENTS.md:66` 和 `.config/pi/AGENTS.md:74` 也记录了归属，维护入口清楚。
- `tmux-subagents` 把运行产物放到 XDG cache/data 路径：`.config/pi/extensions/tmux-subagents/index.ts:77`、`.config/pi/extensions/tmux-subagents/index.ts:85`、`.config/pi/extensions/tmux-subagents/index.ts:93`，没有硬编码到仓库。

#### 🔴 致命问题

- `chain` 协议在提示模板中被当成核心工作流，但自写 `subagent` 工具完全不支持。`.config/pi/prompts/implement.md:5`、`.config/pi/prompts/implement-and-review.md:5`、`.config/pi/prompts/design-review-implement.md:5` 都输出 `{ "chain": [...] }`；而工具声明只有 `agent/task/tasks/action/id/cwd/model/thinking`，见 `.config/pi/extensions/tmux-subagents/index.ts:388` 到 `.config/pi/extensions/tmux-subagents/index.ts:403`，执行分支也只处理 `tasks` 和 `agent + task`，见 `.config/pi/extensions/tmux-subagents/index.ts:464` 和 `.config/pi/extensions/tmux-subagents/index.ts:494`。结果是 AGENTS 中宣称的 worker -> reviewer 等链式流程不可执行。→ 要么实现 `chain`，要么把这些 prompt 改成当前工具支持的 single/parallel 协议。
- agent frontmatter 的 `tools` 被解析后没有传给子 Pi。`discoverAgents()` 解析了 `.config/pi/extensions/tmux-subagents/index.ts:139` 到 `.config/pi/extensions/tmux-subagents/index.ts:147`，但 `buildWrapperCmd()` 只传 `--model`、`--thinking`、`--cwd`，见 `.config/pi/extensions/tmux-subagents/index.ts:187` 到 `.config/pi/extensions/tmux-subagents/index.ts:192`；`subagent-wrapper.sh` 构造 `PI_ARGS` 时也没有 `--tools`，见 `.local/share/pi/scripts/subagent-wrapper.sh:96` 到 `.local/share/pi/scripts/subagent-wrapper.sh:103`。这会让 `scout/planner/oracle` 这类 frontmatter 声明只读工具的 agent 仍拿到默认写入/编辑/执行能力。→ 将 `tools` 显式传入 wrapper，并在 wrapper 中追加 `--tools "$TOOLS"`；缺省时也要考虑是否使用 `--no-tools` 或最小工具集。

#### 🟡 一般问题

- `keepResults` 是配置项但没有任何清理逻辑。它在 `.config/pi/extensions/tmux-subagents/index.ts:37`、`.config/pi/extensions/tmux-subagents/index.ts:72`、`.config/pi/extensions/tmux-subagents/index.ts:105` 出现，后续没有使用。→ 启动或完成后按 mtime 清理 run dir，或者删除这个虚假配置。
- `params.cwd` 在 parallel 模式被声明但不生效。schema 声明了顶层 `cwd`：`.config/pi/extensions/tmux-subagents/index.ts:396`；parallel 分支只使用每个 task 的 `t.cwd`：`.config/pi/extensions/tmux-subagents/index.ts:475`，没有把顶层 cwd 作为默认值传给 `launchParallel()`。→ 使用 `cwd: t.cwd ?? params.cwd`。

### 2. 代码质量

#### ✅ 优点

- shell 脚本整体使用 `set -euo pipefail`，参数大多用数组传递，`.local/share/pi/scripts/subagent-wrapper.sh:96` 到 `.local/share/pi/scripts/subagent-wrapper.sh:117` 避免了把完整 Pi 参数拼成单个 shell 字符串。
- `extract-pi-result.py` 用 `json.loads()` 解析 JSONL，`.local/share/pi/scripts/extract-pi-result.py:11` 到 `.local/share/pi/scripts/extract-pi-result.py:23` 没有用正则硬拆 JSON。

#### 🔴 致命问题

- JSON 模式下的失败会被误报为成功。wrapper 只根据管道退出码写最终状态，见 `.local/share/pi/scripts/subagent-wrapper.sh:146` 到 `.local/share/pi/scripts/subagent-wrapper.sh:159`；extractor 只提取 `message_end` 的 assistant text，完全不检查 `stopReason` / `errorMessage`，见 `.local/share/pi/scripts/extract-pi-result.py:13` 到 `.local/share/pi/scripts/extract-pi-result.py:20`。本机安装的 Pi `print-mode` 在 JSON 模式不会像 text 模式那样把 `stopReason === "error"` 转成非零退出码，因此模型/请求错误可能显示为 completed。→ extractor 应输出结构化结果，至少包含 text、stopReason、errorMessage；wrapper 必须据此判定 failed。
- `waitForCompletion()` 没有超时，也不检查 tmux pane 是否还活着。它只轮询 `status.json`，状态一直是 `running` 或文件不可读时不会结束，见 `.config/pi/extensions/tmux-subagents/index.ts:296` 到 `.config/pi/extensions/tmux-subagents/index.ts:327`。只要 wrapper 缺失、pane 被杀、shell 启动失败、进程卡死，主会话 tool call 就会无限等待。→ 启动前验证 wrapper 可执行；加入超时；轮询 tmux pane 活性；abort 时 kill pane 并写 failed status。

#### 🟡 一般问题

- `tmuxExec(cmd)` 通过 shell 执行 `tmux ${cmd}`，见 `.config/pi/extensions/tmux-subagents/index.ts:164`；`paneTitle` 又从 agent name/config 拼入双引号命令，见 `.config/pi/extensions/tmux-subagents/index.ts:213` 和 `.config/pi/extensions/tmux-subagents/index.ts:217`。当前 agent 名是可信配置时风险有限，但这不是稳健实现。→ 用 `execFileSync("tmux", args)` 或 `spawn` 参数数组。
- `.local/bin/pi-acp:4` 没有转发参数，也没有复用 `PI_LOCAL_ROOT` / `XDG_DATA_HOME` / ensure-installed 逻辑。→ 至少改成 `exec "${PI_LOCAL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/pi}/node_modules/.bin/pi-acp" "$@"`。

### 3. 工程实践

#### ✅ 优点

- JSON 文件可解析：`.config/pi/settings.json`、`.config/pi/models.json`、`.local/share/pi/package.json` 均通过 `JSON.parse`。
- shell 语法通过 `bash -n`；Python helper 通过 `py_compile`；`.local/bin` 和 `.local/share/pi/scripts` 下脚本都有可执行位。
- `~/.local/bin/pi --version` 当前返回 `0.75.4`，说明主 wrapper 在已安装状态下可启动。

#### 🔴 致命问题

- 当前 stow 后运行态缺少 `~/.local/share/pi/package.json`，但 `pi-update` 在 `ROOT_DIR` 下硬读取它。证据：当前 `~/.local/share/pi/package.json` 不存在；`.local/bin/pi-update:62` 执行 `require('./package.json')`，同一命令在 `~/.local/share/pi` 下已复现 `MODULE_NOT_FOUND`。→ 确保 `maak home` 会链接 `.local/share/pi/package.json`，或者让 update 脚本从 dotfiles 源路径/固定 manifest 读取。

#### 🟡 一般问题

- `.config/pi/AGENTS.md:109` 要求修改 extension 后 `cd extensions/xxx && bun run build`，但两个 extension 目录只有 `index.ts`，没有 `package.json`、`tsconfig.json` 或 build script。→ 删除这条要求，或为 extension 补齐可执行的 `package.json` / `tsconfig`。
- `.config/pi/agents/scout.md:6` 和 `.config/pi/agents/researcher.md:6` 使用 `thinking: max`，但当前 Pi 有效值是 `off/minimal/low/medium/high/xhigh`；实测 `--thinking max` 只产生 warning 并被忽略。→ 改成 `xhigh` 或 `high`。
- `.config/pi/AGENTS.md:106` 写着 agent frontmatter 中的 `model` 必须为 zai 模型，但 `.config/pi/agents/scout.md:5`、`.config/pi/agents/researcher.md:5` 使用 deepseek。→ 要么更新约束，要么改回 zai 模型。

### 4. 性能与潜在风险

#### ✅ 优点

- `global-context` 读取失败时不会阻塞启动，见 `.config/pi/extensions/global-context/index.ts:63` 到 `.config/pi/extensions/global-context/index.ts:70`。
- `tmux-subagents` 的 task 内容写入文件再传路径，`.config/pi/extensions/tmux-subagents/index.ts:168` 到 `.config/pi/extensions/tmux-subagents/index.ts:175`，避免把大 task 文本直接塞进 shell 命令。

#### 🔴 致命问题

- parallel 模式没有任务数量上限和并发限制。`SubagentParams` 对 `tasks` 没有 `maxItems`，见 `.config/pi/extensions/tmux-subagents/index.ts:391`；执行时直接为每个 task 开 tmux pane 和 Pi 进程，见 `.config/pi/extensions/tmux-subagents/index.ts:237` 到 `.config/pi/extensions/tmux-subagents/index.ts:263`。这给 LLM 一次工具调用造成资源耗尽的入口。→ 设置最大任务数和最大并发；超过上限直接返回错误。

#### 🟡 一般问题

- `global-context` 没有文件大小、总 token 或文件数量限制。它会读取目录下所有 `.md` 并追加 `extraFiles`，见 `.config/pi/extensions/global-context/index.ts:32` 到 `.config/pi/extensions/global-context/index.ts:56`，再把所有内容拼进 system prompt，见 `.config/pi/extensions/global-context/index.ts:82` 到 `.config/pi/extensions/global-context/index.ts:88`。→ 加 size/token budget，并在注入内容中标注来源文件。
- `global-context` 缺省 `contextDir` 是 `"."`，见 `.config/pi/extensions/global-context/index.ts:27`。配置缺失时会扫描当前工作目录顶层 `.md` 并注入系统提示，这个默认行为过宽。→ 缺省应 no-op，或必须显式设置 `enabled/contextDir`。

## 修复清单

1. **[CRITICAL] `.config/pi/extensions/tmux-subagents/index.ts:388`** - `chain` 工作流声明与工具 schema/执行分支不匹配 - 实现 chain 或修改 prompt 模板。
2. **[CRITICAL] `.local/share/pi/scripts/subagent-wrapper.sh:96`** - agent `tools` frontmatter 未传递，读写权限约束失效 - 传 `--tools` 并设置安全默认工具集。
3. **[CRITICAL] `.config/pi/extensions/tmux-subagents/index.ts:296`** - subagent 等待无超时/无 pane 活性检查 - 加 timeout、状态兜底和 abort kill。
4. **[CRITICAL] `.local/share/pi/scripts/extract-pi-result.py:13`** - JSON 模式错误不进入失败判定 - 提取 stopReason/errorMessage 并让 wrapper 按语义失败。
5. **[CRITICAL] `.config/pi/extensions/tmux-subagents/index.ts:391`** - parallel 无上限 - 添加 max tasks / max concurrency。
6. **[WARNING] `.local/bin/pi-update:62`** - 当前部署缺 `~/.local/share/pi/package.json` 导致 update 直接失败 - 修复 stow/link 或改 manifest 来源。
7. **[WARNING] `.config/pi/extensions/tmux-subagents/index.ts:396`** - parallel 忽略顶层 cwd - 用 `t.cwd ?? params.cwd`。
8. **[WARNING] `.config/pi/extensions/global-context/index.ts:27`** - 缺省扫描当前目录 `.md` - 改成显式启用或无配置 no-op。
9. **[WARNING] `.config/pi/agents/scout.md:6`** - `thinking: max` 非法 - 改为 `xhigh` 或 `high`。
10. **[SUGGESTION] `.local/bin/pi-acp:4`** - 不转发参数且不遵循 XDG/PI_LOCAL_ROOT - 改用 `exec ... "$@"`。

## 是否值得学习

**部分值得。** XDG 路径、tmux 可视化运行、JSONL 提取的方向是可学习的；但当前 subagent 执行器没有达到可靠编排的基本线，特别是权限、失败判定和超时。

## 是否适合用于生产

**不适合自动化或长期无人值守使用。** 个人交互式实验可用，但需要先修复 CRITICAL 项；否则 agent 可能拿到不该有的工具、卡死主会话，或把失败结果当成功继续链式执行。

## 缺失信息

- 未执行真实 LLM subagent 任务：为避免消耗 API 和修改环境，本次只做静态审查、语法校验和无模型调用的 Pi CLI 检查。
- 未确认所有第三方 npm package 的工具命名冲突：本次重点是两个自写 extension 和 wrapper；第三方 package 只用于判断当前运行态。

## 后续建议

- 先修 CRITICAL 1-5，再跑一次最小 E2E：`subagent list`、单个只读 scout、失败模型/无效 cwd、parallel 超限、abort。
- 修复后补一个不调用真实模型的 wrapper 单元测试：伪造 `pi` 命令输出 JSONL，覆盖 success/error/aborted/empty-output。
