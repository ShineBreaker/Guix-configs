<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# crush bash-gate.sh — crush bash 工具拦截 hook（协议适配器）

- 源码：`dotfiles/immutable/agents/.config/crush/hooks/bash-gate.sh`
- 部署：`~/.config/crush/hooks/bash-gate.sh`（immutable，改后须 `blue home`）
- 调用方：crush 的 bash 工具 PreToolUse hook（由 crush.json 注册）
- 决策核：`~/.config/agents/gate-core.sh`（见 [gate-core.md](gate-core.md)）

## 协议（crush 宿主定义，不可改）

| 面     | 形态                                                                                          |
| ------ | --------------------------------------------------------------------------------------------- |
| 输入   | 环境变量 `CRUSH_TOOL_INPUT_COMMAND`（命令文本）；stdin 不用                                    |
| cwd    | `GATE_CWD="${PWD:-$HOME}"`（crush hook 以项目目录为工作目录执行）                               |
| stdout | `{"decision":"allow"}` / `{"context":"..."}` / `{"updated_input":{"command":"..."}}` / `{}`   |
| 拦截   | stderr 输出理由 + exit 2                                                                      |

## 行协议映射

| gate-core 行              | crush 输出                                                                        |
| ------------------------- | --------------------------------------------------------------------------------- |
| `BLOCK`                   | stderr + exit 2                                                                   |
| `AUTO_ALLOW`              | `{"decision":"allow"}` exit 0                                                     |
| `REWRITTEN`（+提示行）    | `{"updated_input":{"command":...}}`（有提示时附带 `"context"`）—crush 真改写命令 |
| `RM_HINT`/`NOTES`/`REDIRECT` | 汇总进 `"context"`（`; ` 连接）                                                |
| 空                        | `{}`                                                                              |

## 设计决策与不变量

- **人工总开关最优先**（覆盖核缺失保底）：`/run/agent-gate.off` 存在 → 输出 `{}` 静默放行，与正常放行同形态，不向 agent 暴露暂停态。各适配器同样硬编固定路径（[gate-core.md §3](gate-core.md)）。
- **核未部署的保底**：`gate-core.sh` 不存在 → `*sudo*` 子串保底拦截（deny），其余命令放行 + stderr 警告——护栏缺失时宁可裸奔带提示也不全拦死。
- `CRUSH_TOOL_INPUT_COMMAND` 为空 → exit 0 放行（空命令无需判定）。
- `set -uo pipefail`（无 `-e`：行协议解析中单行异常不中断）。

## 变更记录

- 2026-10：重构——头部协议说明迁入本文档，注释压缩；行为不变（语料矩阵验证一致）。
