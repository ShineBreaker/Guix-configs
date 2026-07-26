# Cron Error Semantics & JSONC Parser Defect

记录 2026-07-26 诊断 `agent-config-metabolism-weekly` cron job 失败时沉淀的两类可复用知识。

## 1. 脚本 exit(1) 不是 cron 失败，是"有 RED"的正常退出

`metabolism_check.py` 的设计：发现任何 RED 检查项时 `exit(1)`，全部 GREEN 时 `exit(0)`。Hermes cron 把非零退出码标记为 `last_status: "error"`。

**诊断方法**：看脚本输出，不要看 cron 状态码。
- 14 项检查都正常打印 → 脚本跑成功了，`error` 是预期行为
- `[ERROR]` 标签或脚本崩溃 → 真正的故障
- `Script not found` / `Script exited with code 1` 但输出里有完整报告 → 同上，正常

**历史证据**：

| 日期 | cron 状态 | 实际原因 |
|---|---|---|
| 7/12 | Script not found | 裸文件名被解析到 `$HERMES_HOME/scripts/` 下不存在的位置 |
| 7/19 | exit code 1 | 1 RED (微信 poll errors) |
| 7/25 | exit code 1 | 4 RED (inject 超阈值 + JSON 坏 + errors + secrets) |
| 7/26 | exit code 1 | 同上 |

## 2. JSONC 解析器的 `/* */` 块注释盲区

`agent-config-metabolism/scripts/metabolism_check.py` 的 `_parse_json_lenient` 只处理：
- `//` 行注释
- 尾逗号（`,` `]` / `}`）

**不处理** `/* */` 块注释。

这导致 check #6 永久性地把 TypeScript 的 `tsconfig.json` / `tsconfig.node.json` 标记为 "broken JSON"——它们使用块注释分隔编译器选项块（Bundler mode / Path aliases / Linting），但都是合法 JSONC。

**正确修法**：在 `_parse_json_lenient` 里加块注释剥离（正则 `/\*.*?\*/` with DOTALL），不要 exclude `tsconfig*.json`。

## 3. `cronjob` 路径约束文档/实现偏差

`cronjob(action='update', script='/abs/path')` 拒绝绝对路径时报：
> "Script path must be relative to ~/.hermes/scripts/"

但本用户环境中 `~/.hermes/` 目录**不存在**。实际运行时 Hermes 把裸 script 名解析为 `$HERMES_HOME/scripts/<name>`。本用户 `$HERMES_HOME=~/.local/share/hermes`。

**含义**：错误信息里的 `~/.hermes/scripts/` 是文档化约定，实际路径取决于 `$HERMES_HOME`。不要误以为要建 `~/.hermes/` 目录。
