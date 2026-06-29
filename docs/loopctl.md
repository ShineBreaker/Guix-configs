# loopctl — 跨 Agent 迭代循环驱动器

## §0 概述

loopctl 是一个 POSIX sh 实现的 CLI 工具，用于管理**跨 agent 的长期迭代循环**。核心模型是"接力棒"：一个任务被拆成多轮，每轮由一个 agent（通过 adapter 配置）执行，输出自动提取并持久化，状态通过 state.json 跟踪。

**关键约束**：

- POSIX sh 兼容，无 bashism
- 不依赖 jq（JSON 解析用 sed/awk 实现）
- 通过 tmux 分屏提供可视化执行界面

## §1 系统架构

```
┌─────────────────────────────────────────────────────┐
│                    用户 / 调用方                    │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│               loopctl (主入口)                      │
│  路由: help / adapter / list / doctor / <loop> ...  │
└──────┬──────────────────────────────┬───────────────┘
       ▼                              ▼
┌──────────────┐            ┌──────────────────────┐
│  adapter     │            │  loop 生命周期       │
│  管理子命令  │            │  start/next/done/... │
│  list/show/  │            │  state CRUD          │
│  add/test    │            │  tmux driver         │
└──────┬───────┘            └──────────┬───────────┘
       ▼                               ▼
┌──────────────┐            ┌──────────────────────┐
│ adapters/    │            │ state.sh             │
│ *.json       │            │ agent.sh             │
│ (声明式配置) │            │ prompt.sh            │
└──────────────┘            │ (运行时状态管理)     │
                            └──────────┬───────────┘
                                       ▼
                            ┌──────────────────────┐
                            │ 外部 agent CLI       │
                            │ (pi/opencode/crush/…)│
                            └──────────────────────┘
```

## §2 文件结构

### 2.1 源码布局

```
.local/bin/
├── loopctl                      # 主入口 (741 行 POSIX sh)
└── loop_lib/
    ├── common.sh                # 路径常量、JSON 工具、safe_name
    ├── state.sh                 # state.json CRUD
    ├── agent.sh                 # adapter 加载、agent spawn、输出提取
    ├── adapter-cmds.sh          # adapter list/show/add/test 实现
    ├── log.sh                   # 彩色日志输出
    ├── prompt.sh                # 模板渲染
    ├── templates/
    │   ├── task.md.tmpl         # 首轮任务模板
    │   ├── continuation.md.tmpl # 后续轮次模板（含检查点、进展、命令速查）
    │   └── checkpoint.md.tmpl   # 检查点结构模板
    ├── extract/
    │   ├── text.sh              # 纯文本提取
    │   ├── jsonl-last-assistant.sh  # JSONL 最后一条 assistant 消息
    │   ├── jsonl-last-text.sh       # JSONL 最后一条 text 消息
    │   └── claude-code-print.sh     # Claude Code print 输出
    └── tests/                   # 测试脚本
```

### 2.2 配置目录 (`~/.config/loopctl/`)

```
~/.config/loopctl/
└── adapters/
    ├── _TEMPLATE.json           # 新 adapter 模板
    ├── claude-code.json
    ├── codex.json
    ├── crush.json
    ├── omp.json
    ├── opencode.json
    ├── pi.json
    └── README.md
```

### 2.3 运行时目录 (`~/.local/share/loopctl/`)

```
~/.local/share/loopctl/
├── active/                      # 运行中的循环
│   ├── <name>.state.json        # 循环状态
│   └── <name>.task.md           # 任务描述
├── done/                        # 已完成的循环
├── failed/                      # 已失败/已取消的循环
├── archive/                     # 已归档（含时间戳）
└── checkpoints/                 # 检查点符号链接
```

## §3 Adapter 系统

Adapter 是声明式 JSON 文件，描述如何调用一个 agent CLI。每个 adapter 定义了输入方式、参数模板、输出格式、完成标记等。

### 3.1 Adapter JSON Schema

```json
{
  "name": "adapter-name",
  "version": "1.0",
  "description": "...",

  "bin": "agent-cli",
  "bin_check": ["agent-cli", "--version"],
  "bin_min_version": "",

  "run": {
    "args_template": ["-p", "--no-session"],
    "input_method": "stdin | arg | file",
    "input_flag": "--prompt-file",
    "output_format": "text",
    "working_dir": "project_root",
    "timeout_sec": 300
  },

  "extract": {
    "type": "text | jsonl-last-assistant-text | jsonl-last-text | claude-code-print"
  },

  "session": {
    "supported": false,
    "fresh_per_step": true,
    "session_dir_flag": null,
    "resume_flag": null
  },

  "completion": {
    "marker": "<promise>COMPLETE</promise>",
    "marker_scan_tail_chars": 4000,
    "native_command": null
  },

  "env": {},
  "extra_args": [],

  "examples": {
    "smoke_test_prompt": "Reply with exactly: OK"
  }
}
```

### 3.2 字段说明

| 字段                                | 说明                                                       |
| ----------------------------------- | ---------------------------------------------------------- |
| `bin`                               | agent CLI 二进制名（PATH 查找）                            |
| `run.input_method`                  | `stdin`（管道传入）/ `arg`（参数传入）/ `file`（文件传入） |
| `run.input_flag`                    | `file` 模式下的文件参数 flag（如 `--prompt-file`）         |
| `run.args_template`                 | 固定参数数组                                               |
| `run.timeout_sec`                   | 单轮超时（秒），默认 300                                   |
| `extract.type`                      | 输出提取器类型                                             |
| `completion.marker`                 | 完成标记，输出尾部包含此字符串时自动 done                  |
| `completion.marker_scan_tail_chars` | 扫描尾部字符数，默认 4000                                  |
| `session.fresh_per_step`            | `true` = 每轮新会话；`false` = 复用会话                    |
| `session.session_dir_flag`          | 会话目录参数 flag                                          |
| `session.resume_flag`               | 恢复会话参数 flag                                          |

### 3.3 已有 Adapter

| Adapter       | 二进制        | input_method | extract                   |
| ------------- | ------------- | ------------ | ------------------------- |
| `pi`          | `pi`          | stdin        | text                      |
| `opencode`    | `opencode`    | stdin        | jsonl-last-assistant-text |
| `crush`       | `crush`       | stdin        | jsonl-last-assistant-text |
| `claude-code` | `claude-code` | stdin        | claude-code-print         |
| `codex`       | `codex`       | stdin        | text                      |
| `omp`         | `omp`         | stdin        | text                      |

### 3.4 新增 Adapter

1. 复制 `_TEMPLATE.json` 为 `<name>.json`
2. 编辑字段（至少改 `bin` 和 `run.input_method`）
3. 验证：`loopctl adapter test <name>`

## §4 循环生命周期

### 4.1 状态机

```
                  start
                    │
                    ▼
    ┌──────────── active ────────────┐
    │               │                │
    │    pause      │     next       │
    │      │        │       │        │
    │      ▼        │       ▼        │
    │   paused ──resume──► active    │
    │               │                │
    │    done ◄─────┤────► fail      │
    │               │       │        │
    │               │    cancel      │
    │               │       │        │
    │               ▼       ▼        │
    │            done/failed         │
    │               │                │
    │           archive              │
    │               │                │
    └───────────────┘                │
                                     │
     max_iterations 达到 ────────────┘
     completion marker 检测到 ───────┘
```

### 4.2 状态文件 (`state.json`)

```json
{
  "schema_version": 1,
  "name": "loop-name",
  "task": "任务描述",
  "task_file": "/path/to/task.md",
  "agent": "adapter-name",
  "cwd": "/working/directory",
  "status": "active",
  "iteration": 0,
  "max_iterations": 50,
  "completion_marker": "<promise>COMPLETE</promise>",
  "started_at": "2026-06-25T14:30:00Z",
  "last_iteration_at": "",
  "last_iteration_duration_ms": 0,
  "last_iteration_output": "",
  "last_checkpoint": "",
  "git": {
    "repo": "/path/to/repo",
    "branch_at_start": "main",
    "branch": "main"
  },
  "config": {
    "model": "",
    "extra_env": {},
    "spawn_mode": "foreground"
  }
}
```

### 4.3 状态目录流转

| 目录       | 内容          | 触发条件                                     |
| ---------- | ------------- | -------------------------------------------- |
| `active/`  | 运行中的循环  | `start`                                      |
| `done/`    | 已完成        | `done` / 达到 max_iterations / 检测到 marker |
| `failed/`  | 已失败/已取消 | `fail` / `cancel` / 超时                     |
| `archive/` | 已归档        | `archive`（文件名加时间戳）                  |

## §5 执行管线

### 5.1 Tmux 分屏模式

`loopctl <name> start` 后自动进入 tmux 分屏：

```
┌─────────────────────────────────────────┐
│           上方 Pane（agent 执行）       │
│  用户可直接操作 agent CLI               │
│  agent 退出 = 一轮完成                  │
├─────────────────────────────────────────┤
│  底栏 Pane（driver 状态显示）           │
│  ● loop-name | #1/5 | pi                │
│  任务: 重构 auth 模块                   │
│  等待中... 120s                         │
│  loopctl <name> next 下一轮 | ...       │
└─────────────────────────────────────────┘
```

### 5.2 自动循环流程

1. **start** → 创建 state.json + task.md → 启动 tmux 分屏
2. **driver** 在底栏 pane 运行，循环：
   - 检查状态（active/paused/done/failed）
   - 检查迭代上限
   - 渲染 continuation prompt（注入检查点、Git 变更、上轮输出尾部）
   - 在上方 pane 启动 agent
   - 等待 agent 退出（step-done）或用户手动 next（next-trigger）
   - 更新 state.json
3. **完成条件**：
   - 达到 `max_iterations` → 自动 done
   - 输出尾部包含 `completion_marker` → 自动 done
   - agent 进程超时 → 自动 failed

### 5.3 Prompt 渲染

每轮 prompt 通过 `continuation.md.tmpl` 模板渲染，注入以下变量：

| 变量                | 来源                        |
| ------------------- | --------------------------- |
| `${LOOP_NAME}`      | state.json `name`           |
| `${ITERATION}`      | state.json `iteration`      |
| `${MAX_ITERATIONS}` | state.json `max_iterations` |
| `${AGENT}`          | state.json `agent`          |
| `${TASK}`           | state.json `task`           |
| `${CHECKPOINT}`     | 上轮检查点文件内容          |
| `${GIT_SUMMARY}`    | `git diff --stat` 输出      |
| `${OUTPUT_TAIL}`    | 上轮输出尾部（截取）        |
| `${MARKER}`         | completion marker           |

### 5.4 命令构造

根据 adapter 的 `input_method` 构造不同的 shell 命令：

| input_method | 命令格式                                       |
| ------------ | ---------------------------------------------- |
| `stdin`      | `'agent-cli' args < 'prompt-file'`             |
| `arg`        | `agent-cli args 'prompt-file'`                 |
| `file`       | `'agent-cli' args --prompt-file 'prompt-file'` |

### 5.5 输出提取

agent 执行后的原始输出通过 `extract/` 下的脚本提取：

| extract 类型                | 脚本                      | 说明                                  |
| --------------------------- | ------------------------- | ------------------------------------- |
| `text`                      | `text.sh`                 | 直接返回原文                          |
| `jsonl-last-assistant-text` | `jsonl-last-assistant.sh` | JSONL 格式，取最后一条 assistant 消息 |
| `jsonl-last-text`           | `jsonl-last-text.sh`      | JSONL 格式，取最后一条 text 消息      |
| `claude-code-print`         | `claude-code-print.sh`    | Claude Code print 输出格式            |

## §6 命令参考

### 6.1 全局命令

| 命令                   | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| `loopctl help [topic]` | 帮助（topic: adapter / start / loop / general）              |
| `loopctl list [--all]` | 列出活跃循环（`--all` 含已完成/失败/归档统计）               |
| `loopctl doctor`       | 健康检查（目录、adapter、模板、运行中循环、孤立 checkpoint） |

### 6.2 Adapter 管理

| 命令                          | 说明                                                  |
| ----------------------------- | ----------------------------------------------------- |
| `loopctl adapter list`        | 列出所有 adapter + 二进制可用性                       |
| `loopctl adapter show <name>` | 显示 adapter JSON 全文                                |
| `loopctl adapter add <name>`  | 交互式创建新 adapter                                  |
| `loopctl adapter test <name>` | smoke test（实际启动 agent + 提取输出 + 检测 marker） |

### 6.3 循环操作

| 命令                                                        | 说明                                  |
| ----------------------------------------------------------- | ------------------------------------- |
| `loopctl <name> start --task "..." --adapter <a> [options]` | 创建循环                              |
| `loopctl <name> next`                                       | 触发下一轮                            |
| `loopctl <name> status`                                     | 显示 state.json 全文                  |
| `loopctl <name> watch`                                      | 连接到循环的 tmux session             |
| `loopctl <name> done`                                       | 手动标记完成 → 移入 done/             |
| `loopctl <name> fail [reason]`                              | 手动标记失败 → 移入 failed/           |
| `loopctl <name> cancel`                                     | 取消 → 移入 failed/（状态=cancelled） |
| `loopctl <name> pause`                                      | 暂停                                  |
| `loopctl <name> resume`                                     | 恢复暂停                              |
| `loopctl <name> archive`                                    | 归档 → 移入 archive/（含时间戳）      |
| `loopctl <name> checkpoint`                                 | 写入检查点（从 stdin 读取）           |

### 6.4 start 选项

| 选项                   | 说明                                | 默认值   |
| ---------------------- | ----------------------------------- | -------- |
| `--task "描述"`        | 任务描述（与 `--task-file` 二选一） | 必需     |
| `--task-file <path>`   | 从文件读取任务描述                  | —        |
| `--adapter <name>`     | adapter 名称                        | 必需     |
| `--max-iterations <n>` | 最大迭代次数                        | 50       |
| `--cwd <dir>`          | 工作目录                            | 当前目录 |
| `--model <name>`       | 模型名称（透传给 adapter）          | —        |

## §7 检查点机制

检查点是循环的状态快照，用于跨轮次传递进展。

### 7.1 写入检查点

**方式一**：命令行（agent 内部调用）

```bash
echo "检查点内容" | loopctl <name> checkpoint
```

**方式二**：直接写文件

```bash
# 文件路径约定
$XDG_CACHE_HOME/loops/<name>/checkpoint-NNN.md
```

### 7.2 检查点模板

`checkpoint.md.tmpl` 定义了检查点的标准结构：

```markdown
# 检查点: <loop-name> 第 N 轮

## 已完成

- （列出已完成的事项）

## 问题与决策

- （遇到的问题、做出的决策）

## 下一步待办（按优先级排列）

1. （下一步）

## 关键文件

- （重要文件路径）

## 备注

- （经验教训、提醒事项）
```

### 7.3 检查点注入

每轮 prompt 渲染时，上轮检查点内容自动注入到 `${CHECKPOINT}` 变量。首次轮次无检查点时显示空。

## §8 依赖与约束

### 8.1 外部依赖

| 依赖   | 用途             | 必需 |
| ------ | ---------------- | ---- |
| `tmux` | 分屏执行         | 是   |
| `awk`  | JSON 解析        | 是   |
| `sed`  | JSON 解析        | 是   |
| `date` | ISO 时间戳       | 是   |
| `git`  | 分支信息（可选） | 否   |

### 8.2 状态管理约束

- 同名循环不允许重复（需先 done / fail / cancel）
- state.json 字段更新要求字段已存在（`json_set` 前提）
- state.json 移动时 task.md 跟随移动
- 检查点通过符号链接聚合到 `checkpoints/` 目录

### 8.3 Tmux 约束

- 不在 tmux 中时自动创建新 session
- 在 tmux 中时自动分屏（下方 8 行高度）
- driver 通过 pane 间通信控制 agent
- agent 退出信号通过文件系统传递（step-done / next-trigger）

## §9 健康检查 (`doctor`)

`loopctl doctor` 检查以下组件：

| 检查项          | 说明                                            |
| --------------- | ----------------------------------------------- |
| 运行时目录      | active/done/failed/archive/checkpoints 是否存在 |
| Adapter 配置    | JSON 文件是否存在、二进制是否可用               |
| 提取脚本        | 是否可执行                                      |
| 模板文件        | task/continuation/checkpoint .md.tmpl 是否存在  |
| 活跃循环        | 状态是否正常                                    |
| 孤立 checkpoint | 符号链接是否指向有效目标                        |

退出码 = 发现的问题数（0 = 全部正常）。

## §10 与 Atelier 的协同

在 Atelier 的 atelier extension 中，`loopctl` 作为长期迭代循环的驱动层：

```
atelier /loop 命令
  → 检查 loopctl 是否可用
  → 构造 loopctl <name> start 命令
  → 启动循环
  → 通过 loopctl <name> step 触发每轮
```

atelier extension 提供：

- `/loop` 命令：loopctl 前端薄包装
- `/loop-plan` 命令：从 plan 自动创建循环

## §11 使用示例

### 基本用法

```bash
# 查看 adapter 和循环状态
loopctl adapter list
loopctl list --all
loopctl doctor

# 创建并执行一个 3 轮循环
loopctl my-task start --task "重构 auth 模块" --adapter pi --max-iterations 3
loopctl my-task next
loopctl my-task status
loopctl my-task done
```

### 高级用法

```bash
# 从文件读取任务，限制 5 轮
loopctl nightly start --task-file ./task.md --adapter opencode --max-iterations 5

# 指定工作目录
loopctl build start --task "编译并修复错误" --adapter claude-code --cwd ~/project

# 写入检查点
echo "已完成模块 A 的重构" | loopctl my-task checkpoint

# 暂停后恢复
loopctl my-task pause
loopctl my-task resume

# 归档旧循环
loopctl old-task archive
```

### Adapter 管理

```bash
# 列出 adapter
loopctl adapter list

# 查看 adapter 详情
loopctl adapter show pi

# 创建新 adapter
loopctl adapter add my-tool

# 测试 adapter
loopctl adapter test pi
```
