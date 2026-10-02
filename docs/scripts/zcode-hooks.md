<!-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com> -->
<!-- SPDX-License-Identifier: MIT -->

# zcode hooks — zcode 宿主侧的三个 hook

`dotfiles/mutable/agents/zcode/.zcode/hooks/{bash-gate.sh,edit-gate.sh,session-start.sh}` · mutable → `~/.zcode/hooks/`（stow 直链仓库源码，改源即时生效，是活 hook）· 调用方：zcode 宿主

同宿主同目录的三个 hook，共同点是**都从 stdin 读 JSON、都只做协议转换**：判定语义在 `~/.config/agents/gate-core.sh`（见 [gate-core.md](gate-core.md)），注入清单决策在 `~/.config/agents/context-select.sh`（见 [context-select.md](context-select.md)）。`bash-gate.sh` 与 `edit-gate.sh` 是同一模板的两种调用面——骨架逐行同构，实质差异只有 5 点（见下表）；`session-start.sh` 是会话启动钩子，不参与拦截。

## 共享协议

| 面     | 形态                                                                    |
| ------ | ----------------------------------------------------------------------- |
| stdin  | `{"tool_name": ..., "tool_input": {...}, "cwd": ...}`，读空则无待检内容 |
| stdout | 只有 `{"decision":"allow"}`、`{"additionalContext":"..."}`、无输出三种  |
| 拦截   | 理由写 stderr + `exit 2`；放行一律 `exit 0`                             |
| cwd    | 取 `stdin` 的 `cwd`，缺省回退 `$PWD`，再作为 `GATE_CWD` 传给决策核      |

上表是 `bash-gate.sh` 与 `edit-gate.sh` 的完整协议；`session-start.sh` 只有 stdin 的 `cwd` 与 stdout 的 `additionalContext` 两面，没有拦截语义，详见该节。

**fail-closed 三态**（两个 gate hook 相同）：`python3` 不在 PATH → deny；stdin 非空但 JSON 解析失败 → deny（此前 fail-open 是已知绕过面）；stdin 为空 → 不拦，按无待检内容正常放行。解析出的值经 `python3 shlex.quote` 转义后才 `eval`，`eval` 只作用在受控输出上。

**顺序红线**（两个 gate hook）：待检内容为空（`command` 或 `file_path` 为空串）时立刻 `exit 0`，这一步发生在人工总开关检查**之前**；`/run/agent-gate.off` 的存在即静默放行检查必须发生在「核缺失保底」**之前**——暂停态优先于一切降级路径，且零输出、不向 agent 暴露暂停态。

## bash vs edit 的差异

| 维度       | bash-gate.sh                                   | edit-gate.sh                                                       |
| ---------- | ---------------------------------------------- | ------------------------------------------------------------------ |
| 调用面     | Bash 工具 PreToolUse                           | Write/Edit 工具 PreToolUse                                         |
| 待检内容   | `tool_input.command`，作为 `bash` 子命令的参数 | `tool_input.content` 优先、否则 `new_string`，经 stdin 传给 `edit` |
| 核缺失降级 | 命令含 `*sudo*` 子串即 deny，其余放行 + 警告   | 仅警告后放行，路径与敏感检查整体跳过                               |
| 敏感行处理 | 不消费 `SENSITIVE`（bash 模式不产生该类型）    | `BLOCK` 与 `SENSITIVE` 统一 deny exit 2                            |
| 提示类型   | `REWRITTEN`、`RM_HINT`、`NOTES`、`REDIRECT`    | `HINT`                                                             |

## bash-gate.sh

调用 zcode 决策核的 `bash` 子命令。行协议到 zcode 协议的映射：

| gate-core 行                     | zcode 输出                                        |
| -------------------------------- | ------------------------------------------------- |
| `BLOCK`                          | stderr + exit 2                                   |
| `AUTO_ALLOW`                     | `{"decision":"allow"}` 后立刻退出，后续行不再处理 |
| `REWRITTEN`                      | 降级为 `additionalContext` 提示（附改写后的命令） |
| `RM_HINT` / `NOTES` / `REDIRECT` | 汇总进 `additionalContext`，多条以 `; ` 连接      |
| 无输出                           | 无输出                                            |

**zcode 宿主协议没有 `updated_input`**，所以 `REWRITTEN` 拿不到真改写能力，只能把改写后的命令当建议发给模型；pi（`pi-gate` 改写 `event.input.command`）与 hermes（返回 `{"action":"modify"}`）才支持真改写。这是本端与其它端最本质的差异。`RM_HINT` 是决策核不再发出的历史类型，此处保留兼容分支。

核缺失时（`~/.config/agents/gate-core.sh` 不存在，通常是 `blue home` 没跑）先 `sudo` 保底拦截再放行其余命令，警告写 stderr——保底只认 `*sudo*` 子串，不做词序列匹配。

## edit-gate.sh

调用 zcode 决策核的 `edit` 子命令，待检内容从 stdin 传入（可为空，此时只判路径）。行协议映射：

| gate-core 行          | zcode 输出                           |
| --------------------- | ------------------------------------ |
| `BLOCK` / `SENSITIVE` | stderr + exit 2                      |
| `HINT`                | 汇总进 `{"additionalContext":"..."}` |
| 无输出                | 无输出                               |

路径拦截与敏感信息命中**统一 exit 2**，zcode 协议没有单独的敏感码。核缺失时只写一行警告后放行——`gate-core.sh` 的 `sudo` 保底是 bash 侧的事，写入侧没有等价保底。

## session-start.sh

会话启动时把两类信息拼成一条 `{"additionalContext":"..."}` 输出，让 agent 启动即知边界：anchors 防护规则摘要（冻结命令/路径、重定向建议、路径提示、仅人工操作），以及 `context-select.sh --platform zcode --cwd <cwd>` 决策出的全局上下文正文。

| 面     | 形态                                                                               |
| ------ | ---------------------------------------------------------------------------------- |
| stdin  | `{"cwd":"..."}`                                                                    |
| cwd    | stdin `cwd` → `CLAUDE_PROJECT_DIR` → `ZCODE_PROJECT_DIR` → `$PWD`                  |
| stdout | `{"additionalContext":"..."}`（`jq -Rs` 做 JSON 转义）                             |
| 退出码 | 0；本 hook 是 `set -euo pipefail`，与两个 gate hook 的 `set -uo pipefail` 方向相反 |

**fail-open**：本 hook 的 `set -e` 与两个 gate hook「异常即拦」的方向相反——任一未兜底步骤失败就非零退出，宿主按「本次无注入」处理。实际各步骤都自带 `|| true` 或 `&&` 短路保护，所以核缺失、selector 缺失、摘要字段为空这些常见失败不会中断流程。

**cwd 解析链**：`stdin` 的 `cwd` 解析失败或缺省时依次回退 `CLAUDE_PROJECT_DIR`、`ZCODE_PROJECT_DIR`、`$PWD`。

**预算与回退**：单文件 >64 KiB 跳过、总量 >192 KiB 截断，两种情况各往 stderr 记一行（预算对齐 omp）。selector 路径取 `CONTEXT_SELECT_BIN`，未设置时用 `~/.config/agents/context-select.sh`；不可执行时回退直接 cat 恒注入的 `00-core.md` 与 `INDEX.md`（存在才加），保证不空转。`anchors-lib.sh` source 失败时摘要回退 DEFAULT（只有 `sudo` 冻结）。

**摘要字段集**只有 5 组：`frozen_commands`、`frozen_paths`、`redirect_conventions`、`path_hints`、`human_only_actions`。`frozen_globs`、`rewrite`、`interactive_commands`、`bare_repl_commands`、`sensitive_patterns` 不进摘要——摘要只给人看，硬判定一律交给 gate hook。`frozen_paths` 的对象条目渲染成 `path〔cwd 在 <unless_inside> 内豁免〕`，与 agent 实际遇到的判定口径一致；项目名只在 cwd 位于非 `$HOME` 的 git 根内时标注为 `+ 项目 <name>/.agents/anchors.json`。

**暂停态照常输出**：本 hook 不查 `/run/agent-gate.off`，人工总开关存在时摘要仍按拦截态输出——暂停态对 agent 完全不可见，与护栏不存在时表现一致。
