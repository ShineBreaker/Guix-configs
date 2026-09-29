<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# zcode bash-gate.sh — zcode bash 工具拦截 hook（协议适配器）

- 源码：`dotfiles/mutable/agents/zcode/.zcode/hooks/bash-gate.sh`
- 部署：`~/.zcode/hooks/bash-gate.sh`（mutable，stow 直链仓库源码，**改源即时生效——是活 hook**）
- 调用方：zcode 的 Bash 工具 PreToolUse hook
- 决策核：`~/.config/agents/gate-core.sh`（见 [gate-core.md](gate-core.md)）

## 协议（zcode 宿主定义，不可改）

| 面     | 形态                                                              |
| ------ | ----------------------------------------------------------------- |
| stdin  | `{"tool_name":"...","tool_input":{"command":"..."},"cwd":"..."}` |
| stdout | `{"decision":"allow"}` / `{"additionalContext":"..."}` / 无输出   |
| 拦截   | stderr 理由 + exit 2                                              |
| cwd    | `GATE_CWD=<stdin 的 cwd；缺省回退 PWD>`                            |

## 行协议映射

| gate-core 行                       | zcode 输出                                                |
| ---------------------------------- | --------------------------------------------------------- |
| `BLOCK`                            | stderr + exit 2                                            |
| `AUTO_ALLOW`                       | `{"decision":"allow"}`                                     |
| `REWRITTEN`                        | 无改写能力 → 降级为 `additionalContext` 提醒（附改写命令） |
| `RM_HINT`/`NOTES`/`REDIRECT`/`HINT` | 汇总进 `additionalContext`（`; ` 连接）                   |
| 空                                 | 无输出                                                     |

## 设计决策与不变量

- **fail-closed**：python3 缺失或 stdin JSON 非法 → deny（exit 2）——异常态宁可误拦不放行。
- **人工总开关**：`/run/agent-gate.off` → exit 0 静默放行，须在核缺失保底之前检查（[gate-core.md §3](gate-core.md)）。
- **核未部署保底**：`gate-core.sh` 不存在 → `*sudo*` 子串保底拦截，其余放行 + stderr 警告。
- stdin 解析经 python3 `shlex.quote` 生成 `CMD=`/`CWD=` 再 `eval`——`eval` 只在 shlex 转义后的受控输出上执行。
- `set -uo pipefail`（无 `-e`）。

## 变更记录

- 2026-10：重构——头部协议说明迁入本文档，注释压缩；行为不变（语料矩阵验证一致）。
