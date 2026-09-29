<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# crush edit-gate.sh — crush 文件写入拦截 hook（协议适配器）

- 源码：`dotfiles/immutable/agents/.config/crush/hooks/edit-gate.sh`
- 部署：`~/.config/crush/hooks/edit-gate.sh`（immutable，改后须 `blue home`）
- 调用方：crush 的 edit / write / multiedit 工具 PreToolUse hook
- 决策核：`~/.config/agents/gate-core.sh` `edit` 子命令（见 [gate-core.md](gate-core.md)）

## 协议（crush 宿主定义，不可改）

| 面     | 形态                                                                                  |
| ------ | ------------------------------------------------------------------------------------- |
| env    | `CRUSH_TOOL_INPUT_FILE_PATH` / `CRUSH_PROJECT_DIR` / `CRUSH_TOOL_NAME`               |
| stdin  | JSON；待检内容提取：write 取 `tool_input.content`，edit 取 `new_string`，multiedit 拼接 `edits[].new_string` |
| stdout | `{"context":"..."}` / `{}`                                                            |
| 拦截   | stderr + exit 2 = 路径硬拦截；**exit 49 = 敏感信息拦截**（crush 协议专用码）           |
| cwd    | `GATE_CWD="${CRUSH_PROJECT_DIR:-$PWD}"`                                               |

## 行协议映射

| gate-core 行 | crush 输出                          |
| ------------ | ----------------------------------- |
| `BLOCK`      | stderr + exit 2                     |
| `SENSITIVE`  | stderr + **exit 49**                |
| `HINT`       | 汇总进 `{"context":"..."}`（`; ` 连接） |
| 空           | `{}`                                |

## 设计决策与不变量

- **fail-closed**：python3 缺失或 stdin JSON 非法 → deny（exit 2）——crush 输入恒为合法 JSON，异常态宁可误拦不可跳过敏感信息检查。
- **人工总开关**：`/run/agent-gate.off` → `{}` 静默放行（同正常放行形态，须在核缺失降级之前检查）。
- **核未部署**：stderr 警告后放行（路径与敏感信息检查降级跳过）——与 bash-gate 的 sudo 保底不同：edit 无法低成本保底。
- `CRUSH_TOOL_INPUT_FILE_PATH` 为空 → exit 0（无目标文件无需判定）。

## 变更记录

- 2026-10：重构——头部协议说明迁入本文档，注释压缩；行为不变（语料矩阵验证一致）。
