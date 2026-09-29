<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# zcode edit-gate.sh — zcode 文件写入拦截 hook（协议适配器）

- 源码：`dotfiles/mutable/agents/zcode/.zcode/hooks/edit-gate.sh`
- 部署：`~/.zcode/hooks/edit-gate.sh`（mutable，stow 直链仓库源码，**改源即时生效——是活 hook**）
- 调用方：zcode 的 Write/Edit 工具 PreToolUse hook
- 决策核：`~/.config/agents/gate-core.sh` `edit` 子命令（见 [gate-core.md](gate-core.md)）

## 协议（zcode 宿主定义，不可改）

| 面     | 形态                                                                          |
| ------ | ----------------------------------------------------------------------------- |
| stdin  | `{"tool_name":"...","tool_input":{"file_path":"...","content|new_string":"..."},"cwd":"..."}` |
| stdout | `{"additionalContext":"..."}` / 无输出                                        |
| 拦截   | stderr 理由 + exit 2（路径拦截与敏感信息**统一** exit 2——zcode 无 crush 的 49） |
| cwd    | `GATE_CWD=<stdin 的 cwd；缺省回退 PWD>`                                        |

## 行协议映射

| gate-core 行        | zcode 输出                                     |
| ------------------- | ---------------------------------------------- |
| `BLOCK`/`SENSITIVE` | stderr + exit 2                                 |
| `HINT`              | 汇总进 `{"additionalContext":"..."}`            |
| 空                  | 无输出                                          |

## 设计决策与不变量

- **fail-closed**：python3 缺失或 stdin JSON 非法 → deny（exit 2）。
- **人工总开关**：`/run/agent-gate.off` → exit 0 静默放行。
- **核未部署**：stderr 警告后放行（路径与敏感信息检查降级跳过）。
- `file_path` 为空 → exit 0（无目标无需判定）。

## 变更记录

- 2026-10：重构——头部协议说明迁入本文档，注释压缩；行为不变（语料矩阵验证一致）。
