# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>

# SPDX-License-Identifier: MIT

# Extract 脚本说明

每个 extract 脚本接收一个参数（原始输出文件路径），将提取的文本写入 stdout。

| 脚本                      | 适用场景                                                | 对应 extract.type           |
| ------------------------- | ------------------------------------------------------- | --------------------------- |
| `text.sh`                 | 纯文本输出（claude-code --print、echo）                 | `text`                      |
| `jsonl-last-assistant.sh` | pi、codex、opencode 等 JSONL（最后一条 assistant 消息） | `jsonl-last-assistant-text` |
| `jsonl-last-text.sh`      | crush 的 JSONL（最后一行 text 字段）                    | `jsonl-last-text`           |
| `claude-code-print.sh`    | claude-code stream-json 格式                            | `claude-code-print`         |

所有脚本不依赖 jq，使用 POSIX awk/sed 解析。

## 扩展

如果需要新的 extract 类型：

1. 在此目录创建新脚本（如 `my-format.sh`）
2. 在 adapter JSON 中设置 `"extract": { "type": "my-format" }`
3. 脚本名必须与 type 值一致（`-` 替换为 `-`）
4. 脚本必须接收一个参数（文件路径），将提取结果写入 stdout
