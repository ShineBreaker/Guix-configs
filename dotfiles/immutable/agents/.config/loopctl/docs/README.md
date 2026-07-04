# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>

# SPDX-License-Identifier: MIT

# Loop 驱动层 — 跨 Agent 循环执行框架

## 核心理念：接力棒模型

每轮 agent 只读一个文件：**checkpoint（接力棒）**。

```
loopctl: 读 state → 渲染极简 continuation → spawn agent → 收 output → 检测 marker → 更新 state
agent:  读 checkpoint → 干活 → 写新 checkpoint → 可选输出 COMPLETE marker
```

- **state.json** = 元数据指针（iteration、路径、状态）
- **checkpoint.md** = 真正的上下文（已完成、问题、TODO、关键文件、经验）
- **continuation.md** = 极简封面页（< 500 字，指向 checkpoint）

**关键特性**：每次迭代开全新 agent 进程/会话，上下文完全清空，只通过 checkpoint 传递状态。

## 目录结构

```
.agents/workfile/loops/
├── active/                      ← 进行中的 loop state
├── checkpoints/                 ← checkpoint 软链接
├── done/                        ← 已完成
├── failed/                      ← 已失败
└── archive/                     ← 已归档
```

## loopctl 命令速查

### Adapter 管理

```bash
loopctl adapter list              # 列出所有 adapter + bin 可用性
loopctl adapter show <name>       # 显示 adapter 配置
loopctl adapter add <name>        # 交互式生成 adapter
loopctl adapter test <name>       # smoke test
```

### Loop 生命周期

```bash
loopctl <name> start --task "..." --adapter pi [--max-iterations 50] [--cwd <dir>]
loopctl <name> step               # 跑一轮
loopctl <name> status             # 显示状态
loopctl <name> checkpoint --stdin # Agent 写入 checkpoint
loopctl <name> pause / resume     # 暂停/恢复
loopctl <name> done               # 标记完成
loopctl <name> fail [reason]      # 标记失败
loopctl <name> cancel             # 取消
loopctl <name> archive            # 归档
loopctl <name> watch              # tail 最新输出
```

### 跨 Loop

```bash
loopctl list [--all]              # 列出所有 loop
loopctl doctor                    # 健康检查
```

## Adapter 系统

Adapter 是声明式 JSON 配置，描述如何与特定 agent CLI 交互。
**加新 agent = 复制 `_TEMPLATE.json` 改 5-10 个字段**，零脚本。

核心字段：

- `bin`: CLI 可执行文件名
- `run.input_method`: prompt 传递方式（stdin/arg/file）
- `run.args_template`: 固定 CLI 参数
- `extract.type`: 输出提取方式（text/jsonl-last-assistant-text/...）

详见 `drivers/adapters/README.md`。

## 与现有系统的关系

| 机制                 | 关系                                                 |
| -------------------- | ---------------------------------------------------- |
| **atelier subagent** | 正交（subagent = 当前会话内并行，loop = 新会话串行） |
| **atelier workfile** | loop 在 `.agents/workfile/loops/` 子目录工作         |
| **plannotator**      | plan mode 产出的 plan 可作为 loop 的 task 输入       |
| **Ralph Wiggum**     | **被替代**（loop 框架实现了真正的跨会话循环）        |

## 快速开始

```bash
# 1. 创建 adapter（以 echo 为例测试）
loopctl adapter add echo
# → bin: echo, args: (empty), input: stdin, extract: text

# 2. 启动 loop
loopctl test-loop start --task "Say hello" --adapter echo --max-iterations 3

# 3. 跑一轮
loopctl test-loop step

# 4. 查看状态
loopctl test-loop status

# 5. 清理
loopctl test-loop done
```

## 环境变量

| 变量            | 说明                                    |
| --------------- | --------------------------------------- |
| `NO_COLOR`      | 设置任意值关闭彩色输出                  |
| `LOOPCTL_DEBUG` | 设为 `1` 启用 debug 日志                |
| `CTX_*`         | 自动传递给子 agent（context-mode 兼容） |

## 设计约束

- **POSIX sh 兼容**：loopctl 和所有 lib/\*.sh 不使用 bashism
- **无 jq 依赖**：JSON 解析用 awk/sed 实现
- **并发安全**：多个独立 loop 可同时运行，共享 adapters 目录
- **路径基于项目根**：所有路径基于 `state.cwd`（start 时指定），不是 loopctl 所在目录
