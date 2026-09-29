<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# zcode session-start.sh — zcode SessionStart hook

- 源码：`dotfiles/mutable/agents/zcode/.zcode/hooks/session-start.sh`
- 部署：`~/.zcode/hooks/session-start.sh`（mutable，stow 直链仓库源码，**改源即时生效**）
- 调用方：zcode SessionStart 事件
- 协作：`~/.config/agents/anchors-lib.sh`（source 加载规则）+ `~/.config/agents/context-select.sh`（注入清单决策）

## 用途

会话启动时把两类信息拼成 `{"additionalContext":"..."}` 输出，让 agent 启动即知边界：

1. **anchors 防护规则摘要**：冻结命令/路径、重定向建议、路径提示、仅人工操作——与 gate 同一份
   `anchors.json`（全局 + 项目级 ratchet，经 `load_merged_anchors` 加载）。
2. **全局上下文**：`~/.config/agents/context/` 下应由本会话注入的文件正文（清单由
   `context-select.sh --platform zcode --cwd <cwd>` 决策，见 [context-select.md](context-select.md)）。

## 协议

| 面     | 形态                                                                    |
| ------ | ----------------------------------------------------------------------- |
| stdin  | `{"cwd":"..."}`（解析失败/缺省 → `CLAUDE_PROJECT_DIR` → `ZCODE_PROJECT_DIR` → `$PWD`） |
| stdout | `{"additionalContext":"..."}`（jq -Rs JSON 转义）                        |
| exit   | 0（`set -euo pipefail`，任何一步失败即进程退出——host 按无注入处理）      |

## 预算与回退

- 上下文预算对齐 omp：单文件 >64KiB 跳过（stderr 记一行），总量 >192KiB 截断并记一行。
- `context-select.sh` 未部署/不可执行 → 回退直接 cat `00-core.md` + `INDEX.md`（存在才加），保证不空转。
- `anchors-lib.sh` source 失败 → `MERGED` 回退 DEFAULT（仅 sudo）。

## 设计决策与不变量

- **暂停态对 agent 完全不可见**：人工总开关 `/run/agent-gate.off` 存在时摘要仍按拦截态输出——与护栏不存在时表现一致（[gate-core.md §3](gate-core.md)）。
- 摘要里的 `frozen_paths` 对象条目渲染为 `path〔cwd 在 unless_inside 内豁免〕`，与 agent 视角一致。
- 项目名仅当 cwd 位于非 `$HOME` 的 git 根内时标注（`+ 项目 <name>/.agents/anchors.json`）。

## 变更记录

- 2026-10：重构——头部用途/预算说明迁入本文档，注释压缩；行为不变（语料矩阵验证一致）。
