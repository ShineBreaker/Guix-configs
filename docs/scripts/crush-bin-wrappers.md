<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# crush/bin/* — LSP / MCP 转发器族（11 个同构入口）

- 源码：`dotfiles/immutable/agents/.config/crush/bin/`（11 个文件）
- 部署：`~/.config/crush/bin/`（immutable，改后须 `blue home`）
- 调用方：crush 的 LSP / MCP 配置按命令名寻址这些入口

## 用途与形态

11 个文件完全同构，统一四行：

```bash
#!/usr/bin/env bash
set -euo pipefail

exec ~/.guix-home/profile/bin/npx --yes -p <package> <command> "$@"
```

| 入口                                | `-p <package>` → `<command>`                                    |
| ----------------------------------- | --------------------------------------------------------------- |
| `bash-language-server`              | `bash-language-server` → `bash-language-server`                 |
| `typescript-language-server`        | `typescript` + `typescript-language-server` → `typescript-language-server` |
| `vscode-css-language-server`        | `vscode-langservers-extracted` → `vscode-css-language-server`   |
| `vscode-eslint-language-server`     | `vscode-langservers-extracted` → `vscode-eslint-language-server` |
| `vscode-html-language-server`       | `vscode-langservers-extracted` → `vscode-html-language-server`  |
| `vscode-json-language-server`       | `vscode-langservers-extracted` → `vscode-json-language-server`  |
| `vscode-markdown-language-server`   | `vscode-langservers-extracted` → `vscode-markdown-language-server` |
| `context7-mcp`                      | `@upstash/context7-mcp` → `context7-mcp`                        |
| `filesystem-mcp`                    | `@modelcontextprotocol/server-filesystem` → `mcp-server-filesystem` |
| `mcp-server-memory`                 | `@modelcontextprotocol/server-memory` → `mcp-server-memory`     |
| `mcp-server-sequential-thinking`    | `@modelcontextprotocol/server-sequential-thinking` → `mcp-server-sequential-thinking` |

注：`typescript-language-server` 需要两个 `-p`（`typescript` 是对等依赖），其余入口单包即可。

## 设计决策

- **`npx --yes -p` 按需取包**：不依赖项目内 node_modules，crush 开箱即用；`exec` 转发保持进程语义（信号/退出码直达）。
- **部署形态是独立 store 项**：每个文件由 home-dotfiles 复制进 store 后软链，`$0` 相对关系不可用——这正是它们用 `~/.guix-home/profile/bin/npx` 绝对路径的原因。
- 族内无差异逻辑，**不**加 per-file 头注释——本篇即共同文档（CONVENTIONS §2：同构小文件合并一篇）。

## 变更记录

- 2026-10：无代码改动；本篇为新增文档。
