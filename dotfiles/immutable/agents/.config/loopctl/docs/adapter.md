<!-- SPDX-FileCopyrightText: 2026 BrokenShine -->
<!-- SPDX-License-Identifier: MIT -->

# Adapter JSON Schema

loopctl 通过声明式 JSON 文件适配不同 agent CLI。新 adapter = 复制 `_TEMPLATE.json` 改 5-10 个字段。

## 顶层字段

| 字段              | 类型     | 必填 | 说明                                          |
| ----------------- | -------- | ---- | --------------------------------------------- |
| `name`            | string   | ✅   | adapter 唯一标识，对应文件名                  |
| `version`         | string   | ✅   | schema 版本，当前固定 `"1.0"`                 |
| `description`     | string   | ✅   | 人类可读描述                                  |
| `bin`             | string   | ✅   | CLI 可执行文件名（需在 `$PATH` 中）           |
| `bin_check`       | string[] | ✅   | 验证 CLI 可用的命令，如 `["pi", "--version"]` |
| `bin_min_version` | string   | ❌   | 最低版本要求（语义化版本比较）                |

## `run` — 执行配置

控制 loopctl 如何 spawn agent 进程。

| 字段            | 类型         | 默认值         | 说明                                                                      |
| --------------- | ------------ | -------------- | ------------------------------------------------------------------------- |
| `args_template` | string[]     | `[]`           | 固定 CLI 参数（不含 prompt 相关）                                         |
| `input_method`  | enum         | —              | prompt 传递方式：`stdin` / `arg` / `file`                                 |
| `input_flag`    | string\|null | `null`         | `arg` 或 `file` 模式下的 flag 名（如 `-p`、`--prompt-file`）              |
| `output_format` | enum         | —              | 输出格式：`text` / `jsonl`                                                |
| `working_dir`   | enum         | `project_root` | 工作目录基准：`project_root`（state.cwd）或 `inherit`（loopctl 当前目录） |
| `timeout_sec`   | int          | `300`          | 单步超时秒数（0=无限），超时发 SIGTERM→SIGKILL                            |

### `input_method` 详解

| 值      | 行为                                               | `input_flag`                    |
| ------- | -------------------------------------------------- | ------------------------------- |
| `stdin` | prompt 通过管道传入 stdin                          | 忽略                            |
| `arg`   | prompt 作为命令行参数，通过 `input_flag` 指定 flag | 如 `"-p"` 或 `null`（直接追加） |
| `file`  | prompt 写入临时文件，通过 `input_flag` 传文件路径  | 如 `"--prompt-file"`            |

## `extract` — 输出提取

从 agent 原始输出中提取最终 assistant 文本。

| 字段   | 类型   | 必填 | 说明                                         |
| ------ | ------ | ---- | -------------------------------------------- |
| `type` | enum   | ✅   | 提取器类型（见下表）                         |
| `jq`   | string | ❌   | 当 `type=custom` 时的 jq 表达式（需安装 jq） |

### 预定义 extract 类型

| type                        | 适用场景                                                                | 实现                      |
| --------------------------- | ----------------------------------------------------------------------- | ------------------------- |
| `text`                      | 纯文本输出（如 `cat`、`echo`）                                          | 直接读取全部输出          |
| `jsonl-last-assistant-text` | pi / codex / opencode 等 JSONL，提取最后一条 assistant 消息的 text 字段 | 解析 JSONL 过滤 assistant |
| `jsonl-last-text`           | crush 的 JSONL 格式                                                     | 取最后一行完整文本        |
| `claude-code-print`         | claude-code `--output-format stream-json`                               | 解析 stream-json 事件流   |
| `custom`                    | 用户自定义                                                              | 执行 `extract.jq` 表达式  |

## `session` — 会话管理

| 字段               | 类型         | 默认值  | 说明                                                |
| ------------------ | ------------ | ------- | --------------------------------------------------- |
| `supported`        | bool         | `false` | 该 CLI 是否有 session 概念                          |
| `fresh_per_step`   | bool         | `true`  | 每轮是否开全新 session（推荐 true，避免上下文泄漏） |
| `session_dir_flag` | string\|null | `null`  | 指定 session 目录的 flag（如 `--session-dir`）      |
| `resume_flag`      | string\|null | `null`  | 恢复 session 的 flag（如 `--resume`、`--continue`） |

## `completion` — 完成检测

| 字段                     | 类型         | 默认值 | 说明                                       |
| ------------------------ | ------------ | ------ | ------------------------------------------ |
| `marker`                 | string       | —      | 文本标记，agent 输出包含此串即视为任务完成 |
| `marker_scan_tail_chars` | int          | `4000` | 仅扫描输出末尾 N 字符（防止正文误触发）    |
| `native_command`         | string\|null | `null` | 预留：某些 agent 有原生循环机制            |

## `env` — 环境变量

注入到 agent 进程的环境变量。值中的 `${VAR}` 由 loopctl 用 POSIX `envsubst` 展开。

```json
"env": {
  "OPENAI_API_KEY": "${OPENAI_API_KEY}",
  "CUSTOM_CONFIG": "/etc/myapp/config.yml"
}
```

**展开规则**：

- `${VAR}` → 取 loopctl 进程的环境变量 `VAR` 的值
- 未定义的变量展开为空字符串
- 不支持默认值语法（`${VAR:-default}`），需在 shell 层预设

## `extra_args` — 额外参数

用户通过 `--extra-args` 传入的附加 CLI 参数，追加到 `args_template` 之后。

```json
"extra_args": []
```

## `examples` — 测试用例

| 字段                | 类型   | 说明                                         |
| ------------------- | ------ | -------------------------------------------- |
| `smoke_test_prompt` | string | `loopctl adapter test` 使用的简单验证 prompt |

---

## 完整示例：pi.json

```json
{
  "name": "pi",
  "version": "1.0",
  "description": "Pi Coding Agent",

  "bin": "pi",
  "bin_check": ["pi", "--version"],
  "bin_min_version": "0.75.5",

  "run": {
    "args_template": ["-p", "--mode", "json", "--no-session"],
    "input_method": "arg",
    "input_flag": null,
    "output_format": "jsonl",
    "working_dir": "project_root",
    "timeout_sec": 600
  },

  "extract": {
    "type": "jsonl-last-assistant-text"
  },

  "session": {
    "supported": true,
    "fresh_per_step": true,
    "session_dir_flag": "--session-dir",
    "resume_flag": "--resume"
  },

  "completion": {
    "marker": "<promise>LOOP_COMPLETE</promise>",
    "marker_scan_tail_chars": 4000,
    "native_command": null
  },

  "env": {},

  "extra_args": [],

  "examples": {
    "smoke_test_prompt": "Reply with exactly: OK"
  }
}
```

## 添加新 adapter 的 3 步

```bash
# 1. 复制模板
cp drivers/adapters/_TEMPLATE.json drivers/adapters/myagent.json

# 2. 编辑 5 个核心字段
#    bin / run.args_template / run.input_method / extract.type / completion.marker

# 3. 测试
loopctl adapter test myagent
```
