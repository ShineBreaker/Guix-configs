# SPDX-FileCopyrightText: 2026 brokenshine <brokenshine@users.noreply.codeberg.org>

# SPDX-License-Identifier: MIT

# Adapter 开发指南

## 什么是 adapter？

adapter 是一份声明式 JSON 配置，描述如何与特定的 agent CLI 交互。
loopctl 通过 adapter 配置知道：怎么启动 agent、怎么传入 prompt、怎么提取输出、怎么检测完成。

## 3 步加新 adapter

### 方法 A：交互式生成（推荐）

```bash
loopctl adapter add myagent
# → 回答 5 个问题 → 自动生成 adapters/myagent.json
```

### 方法 B：手动复制模板

```bash
cp adapters/_TEMPLATE.json adapters/myagent.json
# 编辑以下字段：
```

### 必须编辑的字段

| 字段                | 说明                         | 示例                                     |
| ------------------- | ---------------------------- | ---------------------------------------- |
| `name`              | adapter 名称（与文件名一致） | `"pi"`                                   |
| `bin`               | CLI 可执行文件名             | `"pi"`                                   |
| `run.args_template` | 固定 CLI 参数                | `["--mode", "json"]`                     |
| `run.input_method`  | prompt 传递方式              | `"stdin"` / `"arg"` / `"file"`           |
| `run.input_flag`    | 当 method=arg/file 时的 flag | `"--prompt-file"` / `null`               |
| `run.output_format` | 输出格式                     | `"text"` / `"jsonl"`                     |
| `extract.type`      | 提取器类型                   | `"text"` / `"jsonl-last-assistant-text"` |

### 可选字段

| 字段                       | 默认值                        | 说明                                 |
| -------------------------- | ----------------------------- | ------------------------------------ |
| `run.timeout_sec`          | 300                           | 单步超时（秒），0=无限               |
| `completion.marker`        | `<promise>COMPLETE</promise>` | 完成标记                             |
| `session.session_dir_flag` | null                          | 指定 session 目录的 flag             |
| `session.resume_flag`      | null                          | 恢复 session 的 flag                 |
| `env`                      | {}                            | 注入的环境变量（支持 `${VAR}` 展开） |

### 验证

```bash
loopctl adapter test myagent
# → 用 smoke_test_prompt 跑一次
```

## input_method 详解

| 方法    | 行为                                  | 适用场景                                    |
| ------- | ------------------------------------- | ------------------------------------------- |
| `stdin` | `cat prompt.md \| $bin $args`         | codex 等支持 stdin 的 CLI                   |
| `arg`   | `$bin $args $flag "$prompt_content"`  | 短 prompt，CLI 支持 prompt 作为参数         |
| `file`  | `$bin $args $flag /path/to/prompt.md` | pi、claude-code 等支持 --prompt-file 的 CLI |

## extract.type 详解

| 类型                        | 行为                                   | 适用 CLI                  |
| --------------------------- | -------------------------------------- | ------------------------- |
| `text`                      | 直接 cat                               | claude-code --print、echo |
| `jsonl-last-assistant-text` | JSONL 中最后一条 assistant 消息的 text | pi、codex、opencode       |
| `jsonl-last-text`           | JSONL 最后一行的 text 字段             | crush                     |
| `claude-code-print`         | claude-code stream-json 格式           | claude-code               |

## 常见问题

**Q: adapter 的 bin 不在 PATH 怎么办？**
A: 使用完整路径，如 `"bin": "/usr/local/bin/myagent"`。

**Q: agent 需要 API key 怎么配置？**
A: 在 `env` 字段中声明，值支持 `${VAR}` 引用环境变量：

```json
"env": { "MY_API_KEY": "${MY_API_KEY}" }
```

loopctl 会用 envsubst 展开。

**Q: 怎么测试 adapter 配置是否正确？**
A: `loopctl adapter test <name>` 会用 `examples.smoke_test_prompt` 跑一次，
验证 spawn → extract → marker 检测全流程。
