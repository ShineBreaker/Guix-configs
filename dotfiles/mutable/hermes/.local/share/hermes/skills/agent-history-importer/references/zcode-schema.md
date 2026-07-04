# zcode (`~/.zcode/cli/db/db.sqlite`) — schema 报告

**侦察时间:** 2026-07-04
**zcode DB 大小:** ~86 MB
**侦察样本 session:** `sess_6a94a941-6987-4607-9ed4-a1fc95236422`("distrobox 容器环境配置", 375 msgs)
**全局规模:** 102 sessions (31 parent + 71 subagent) / 6768 messages / 25874 parts

---

## 1. 三表 DDL

```sql
CREATE TABLE session (
  id text primary key,
  project_id text not null,
  workspace_id text, parent_id text,
  slug text not null, directory text not null, path text,
  title text not null, version text not null, share_url text,
  summary_additions integer, summary_deletions integer, summary_files integer, summary_diffs text,
  revert text, permission text,
  time_created integer not null, time_updated integer not null,
  time_compacting integer, time_archived integer,
  task_type text not null default 'interactive',
  title_source text not null default 'first_input'
    check(title_source in ('default','first_input','generated','custom')),
  title_message_id text, time_title_updated integer, trace_id text
);

CREATE TABLE message (
  id text primary key,
  session_id text not null references session(id) on delete cascade,
  time_created integer not null, time_updated integer not null,
  data text not null   -- JSON
);

CREATE TABLE part (
  id text primary key,
  message_id text not null references message(id) on delete cascade,
  session_id text not null,    -- 冗余存一份,方便查询
  time_created integer not null, time_updated integer not null,
  data text not null   -- JSON
);
```

`message.data` 和 `part.data` 都是 JSON TEXT,**没有 DDL 层面的 schema**。结构完全靠 `type` / `role` 字段区分。

---

## 2. `message.data.role` 的所有取值

**只有 `user` 和 `assistant`。没有 `system` role 的顶层 message。**

| role      | 全局 | 目标 session |
| --------- | ---- | ------------ |
| assistant | 6119 | 341          |
| user      | 649  | 34           |

---

## 3. `part.data.type` 的所有取值 + 字段形状

### 全局分布

| type        | 数量 |
| ----------- | ---- |
| tool        | 7354 |
| step-start  | 6105 |
| step-finish | 6063 |
| text        | 5678 |
| reasoning   | 639  |
| compaction  | 28   |
| file        | 7    |

### 3.1 `step-start` — 21 字节

```json
{ "type": "step-start" }
```

仅一个 marker,标记一轮 assistant turn 开始。

### 3.2 `step-finish` — 终止 + cost/token 统计

```json
{
  "type": "step-finish",
  "reason": "stop",
  "cost": 0,
  "tokens": {
    "total": 18699,
    "input": 18235,
    "output": 464,
    "reasoning": 0,
    "cache": { "read": 8064, "write": 0 }
  }
}
```

`reason` 通常是 `stop`,也可能是 `length` / `content-filter` / `tool-calls` 等。

### 3.3 `text` — 普通文本块

```json
{
  "type": "text",
  "text": "已加载 distrobox 容器环境约束。当前关键点我记下了：\n\n- 我在 `my-distrobox`（Arch）容器内，宿主机是 Guix System，共享同一 HOME\n- `emacs` / `emacsclient` / `herd` / `blue` / `guix` 都要走 `host-spawn ...`\n- 文件读写不用 host-spawn，只有执行宿主二进制才需要\n- `blue home` 必须在 `~/Projects/Config/Guix-configs/` 仓库根跑\n\n请告诉我你想做什么 —— 比如改某个 `.el` 模块、修 bug、加功能，还是排查启动问题？",
  "time": { "start": 1782229014686, "end": 1782229025318 }
}
```

- assistant text 不带 `synthetic` 字段
- user text 可能带 `synthetic:true`(系统注入,见 §6)

### 3.4 `reasoning` — 思考链

```json
{
  "type": "reasoning",
  "text": "The user message appears to be a system reminder about the distrobox environment, but there's no actual user question or task yet. Let me look more carefully...\n\nLooking at the conversation, the only thing present is:\n1. System reminders about skills available\n2. The `/distrobox` skill command output describing the container environment\n\nThere's no actual user question or task to respond to. The `/distrobox` command was run which just loads context about the environment. There's no explicit user question following it.\n\nI should respond briefly acknowledging the environment context is now loaded and ask what the user wants to do. I don't need to invoke any skill since there's no creative work or task yet - this is just acknowledging environment setup.\n\nLet me keep it brief and in Chinese since the context is in Chinese.",
  "time": { "start": 1782229014686, "end": 1782229025309 }
}
```

### 3.5 `tool` — 工具调用(**单一来源**)

callID 命名:`call_<24-28 位 hex>`,例如 `call_c8eb7d1b750842e79f97a04d`。

**简单工具样本(Grep):**

```json
{
  "type": "tool",
  "callID": "call_ca17d1d7e82746b087158f2c",
  "tool": "Grep",
  "state": {
    "status": "completed",
    "input": { "pattern": "indent-bars", "output_mode": "files_with_matches" },
    "output": "Found 3 files\ndiagnose/test-config-loading.el\nconfigs/editor/navigation.el\nREADME.org",
    "title": "Grep",
    "metadata": {
      "schemaVersion": 1,
      "serialization": {
        "truncated": false,
        "originalBytes": 85,
        "returnedBytes": 85,
        "budgetStrategy": "artifact"
      }
    },
    "time": { "start": 1782229384806, "end": 1782229384919 }
  }
}
```

**Skill 工具样本(input 是对象,output 是长文本):**

```json
{
  "type": "tool",
  "callID": "call_c8eb7d1b750842e79f97a04d",
  "tool": "Skill",
  "state": {
    "status": "completed",
    "input":  {"skill": "systematic-debugging"},
    "output": "<skill_content name=\"systematic-debugging\">\n# Skill: systematic-debugging\n# Systematic Debugging\n\n## Overview\n\nRandom fixes waste time and create new bugs. Quick patches mask underlying issues.\n\n**Core principle:** ALWAYS find root cause before attempting fixes. Symptom fixes are failure.\n\n## When to Use\n\nUse for ANY technical issue:\n- Test failures\n- Bugs in production\n- Unexpected behavior\n- Performance problems\n- Build failures\n- Integration issues\n...",
    "title": "Skill",
    "metadata": {"schemaVersion": 1, "serialization": {"truncated": false, "originalBytes": ..., "returnedBytes": ..., "budgetStrategy": "artifact"}},
    "time": {"start": ..., "end": ...}
  }
}
```

字段要点:

- `state.status` ∈ `completed`/`running`/`error`/`cancelled`
- `state.input` 始终是 **JSON 对象**(即使是 Bash 也是 `{cmd: ..., ...}`)
- `state.output` 是 **字符串**(可能很长,经常包含原始 stdout 或 JSON)
- `state.time.{start,end}` 是 ms,**与 part.time_created 无关**
- `state.metadata.serialization.budgetStrategy` 提示是否被截断

### 3.6 `compaction` — 上下文压缩事件

```json
{
  "type": "compaction",
  "auto": false,
  "trigger": "manual",
  "phase": "standalone_turn",
  "compactReason": "user_requested",
  "tail_start_id": "msg_mqrb73wc_56261497-a14a-4a41-b9bb-68b991d317f2",
  "compactBoundary": {
    "boundaryId": "compact_a1a1de96-055f-4ee0-a9e9-b65fe5a76bb2",
    "trigger": "manual",
    "phase": "standalone_turn",
    "compactReason": "user_requested",
    "summarySource": "model",
    "preCompactTokenCount": 56904,
    "postCompactTokenCount": 126336,
    "truePostCompactTokenCount": 8737,
    "summarizedMessageCount": 426,
    "keptMessageCount": 0,
    "lastSummarizedMessageId": "msg_mqrb73wc_...",
    "summaryMessageIds": ["msg_mqrzsj3q_..."],
    "customInstructions": false,
    "traceId": "810f62f4-...",
    "turnId": "turn_5f04a908-..."
  },
  "operationId": "cmp_8d16a061-874a-4e5c-8a9a-eba465199123"
}
```

### 3.7 `file` — 用户上传附件(全局仅 7 条)

```json
{
  "type": "file",
  "mime": "image/png",
  "filename": "2026-06-16_18-42-16.png",
  "url": "zcode-artifact://sess_a8823189-4c38-49d0-8949-83fac843b787/tool-result-76859e80-...",
  "source": {
    "type": "file",
    "path": "/home/brokenshine/Pictures/Screenshots/2026-06-16_18-42-16.png",
    "text": {
      "value": "/home/brokenshine/Pictures/Screenshots/2026-06-16_18-42-16.png",
      "start": 0,
      "end": 62
    }
  },
  "metadata": {
    "image": {
      "height": 1507,
      "maxDimension": 2048,
      "originalHeight": 1796,
      "originalWidth": 2440,
      "resized": true,
      "transformedSizeBytes": 366613,
      "width": 2048
    },
    "originalUrl": "/home/brokenshine/Pictures/Screenshots/2026-06-16_18-42-16.png",
    "recoverability": "provider_ready",
    "sha256": "sha256:10bc2a108f8425080fd1ab792a34fffca1903d5067e73af9d745aec811ba7cdf",
    "sizeBytes": 264304,
    "storageKind": "artifact",
    "artifactUri": "zcode-artifact://sess_a8823189-4c38-49d0-8949-83fac843b787/tool-result-76859e80-58d4-4a28-9c48-9469e8cd7adb"
  }
}
```

---

## 4. Tool call 存储位置 — 单一真相

**`message.data.tool_calls` 顶层字段在 DB 中 100% 为 NULL**(6768/6768 messages)。

```sql
SELECT json_extract(m.data,'$.tool_calls') IS NULL, COUNT(*)
FROM message m GROUP BY 1;
-- 1 | 6768
```

→ **`part.type="tool"` 是 tool call 的唯一来源**。一个 assistant message 包含 N 个 tool calls = N 个 part.type=tool,可由 `part.time_created` 排序后用 `state.time.start` 二次排序。

---

## 5. User message 的 part 拆分

| 模式                            | 数量(目标 session 34 条 user) |
| ------------------------------- | ----------------------------- |
| 单一 text part                  | 33                            |
| text + 紧跟一个 compaction part | 1                             |

→ 普通 user prompt 是**单 part**。**不需要合并**。

例外(target session 唯一一例 `msg_mqrzsj3q_...` at 1782300655286):text part 8635 chars("This session is being continued from a previous conversation that was compacted. The summary below...")+ compaction part。这是用户手动 /compact 后,summary 以"伪 user prompt"形式重新注入。可作为普通 user 渲染,标记 `is_compaction_continuation=true`。

---

## 6. System 信息的存储方式

**zcode 没有 `role=system` 的 message。** "系统信息"分两种来源:

### 6.1 自动注入 → 作为 user message,text part 带 `synthetic:true`

```json
{
  "type": "text",
  "text": "<system-reminder>\nThe TodoWrite tool hasn't been used recently. If you're working on tasks that would benefit from tracking progress, consider using the TodoWrite tool to track progress. Also consider cleaning up the todo list if has become stale and is no longer matches what you are working on. Only use if it's relevant to the current work. This is just a gentle reminder - ignore if not applicable.\n</system-reminder>",
  "synthetic": true,
  "time": { "start": 1782229629964, "end": 1782229629964 },
  "metadata": {
    "runtimeMessage": { "source": "todo_reminder" },
    "source": "todo_reminder",
    "visibility": "model-only"
  }
}
```

全局统计(按 part):synthetic user text = 412 / 非 synthetic user text = 237 / assistant text = 5029。

**Importer 策略:** 渲染时把 `synthetic=true` 的 user 文本折叠为 `<system-reminder>...</system-reminder>` 块或折叠成侧栏,避免污染对话流。

### 6.2 Slash command(如 `/distrobox`)→ 也是 user message,但文本含"Run custom command"装饰

```json
{
  "type": "text",
  "text": "Run custom command /distrobox.\nCommand source: user/zcode.\n\n## 运行环境：distrobox 容器（硬约束）\n\n<critical>\n你（ZCode agent）当前运行在一个 **distrobox / podman 容器** 中，...\n</critical>\n\n### 环境证据（已实测）\n...",
  "time": { "start": 1782229014676, "end": 1782229014676 }
}
```

**没有 `synthetic:true`** —— 这是真实的用户输入,只是命令解析后被改写成展开文本。**Importer 应保留为普通 user。**

---

## 7. 时间单位 — 毫秒(ms since epoch)

**直接验证:**

```sql
SELECT (m2.time_created - m1.time_created) AS delta_ms,
       datetime(m1.time_created/1000, 'unixepoch') AS iso
FROM message m1, message m2
WHERE m1.id='msg_mqqt50us_dd6a5f0a-d863-45e5-8b78-6fb48dd0c25b'
  AND m2.id='msg_mqqt50v2_3f550edc-21f7-45a2-ac9e-4ed03afe0719';
-- 10 | 2026-06-23 15:36:54
```

所有时间字段都是 ms:`message.time_created/updated`、`part.time_created/updated`、`part.time.start/end`、`session.time_*`。

---

## 8. Assistant message 的顶层元数据

每条 assistant message 都带:

```json
{
  "role": "assistant",
  "time": { "created": 1782229014686, "completed": 1782229025330 },
  "parentID": "msg_mqqt50us_dd6a5f0a-d863-45e5-8b78-6fb48dd0c25b",
  "modelID": "GLM-5.2",
  "providerID": "builtin:bigmodel-coding-plan",
  "mode": "build", // 或 "yolo"
  "agent": "zcode-agent",
  "path": {
    "cwd": "/home/brokenshine/Projects/Config/Guix-configs/stow/emacs/.config/emacs",
    "root": "/home/brokenshine/Projects/Config/Guix-configs/stow/emacs/.config/emacs"
  },
  "cost": 0,
  "tokens": {
    "total": 18699,
    "input": 18235,
    "output": 464,
    "reasoning": 0,
    "cache": { "read": 8064, "write": 0 }
  },
  "finish": "stop"
}
```

覆盖度(目标 session 341 条 assistant):parentID/mode/cost/modelID/tokens/path 全 100%,finish 339/341(其余 2 条未完成/streaming)。

**`parentID` 等价于"上一条 user message"**,可直接用来配对话轮次。

---

## 9. User message 的 per-turn env metadata

每条 user message 都带 `contextSnapshot.envInfo` + `tools`(与 session.directory 不一定一致):

```json
{
  "role": "user",
  "time": {"created": 1782229014676},
  "agent": "zcode-agent",
  "model": {"providerID": "builtin:bigmodel-coding-plan", "modelID": "GLM-5.2"},
  "contextSnapshot": {
    "envInfo": {
      "cwd": "/home/brokenshine/Projects/Config/Guix-configs/stow/emacs/.config/emacs",
      "platform": "linux", "shell": "fish",
      "osVersion": "linux 7.0.12 x64", "nodeVersion": "v24.14.0",
      "isGitRepository": true, "gitBranch": "main", "gitMainBranch": "main",
      "gitStatus": "clean", "gitStatusLines": [],
      "recentCommits": ["8a0f6c5 FIX: fit for `XDG Directory`", ...]
    }
  },
  "tools": {
    "Read": true, "Write": true, "Edit": true, "Bash": true, "Glob": true, "Grep": true,
    "WebFetch": true, "WebSearch": true, "TodoRead": true, "TodoWrite": true,
    "EnterPlanMode": true, "ExitPlanMode": true, "AskUserQuestion": true,
    "ReadSessionContext": true, "Agent": true, "Skill": true
  }
}
```

**关键发现:envInfo.cwd 是 turn-level 的快照,不是 session 级。** 在目标 session 的最后一条 assistant 中,`path.cwd` 变成了 `/data/Projects/Config/...`(与 session.directory 不一致,应该是工作区被挂载到两个路径)。

**Importer 建议:**

- session 级别的 cwd 用 `session.directory`(稳定)
- 如果做"会话中 cd 了"的可视化,从 assistant `path.cwd` 抽取时序变化
- `recentCommits` / `gitStatus` / `tools` 完全是 prompt-side context,**不要写进 message content**,最多记成 metadata

---

## 10. Subagent session 的结构

目标 session 有一个 subagent child:

```
sess_subagent_agent_3d6b1412-7725-4083-b99d-4cb139009596
  parent_id = sess_6a94a941-6987-4607-9ed4-a1fc95236422
  task_type = 'subagent_child'
  title = "你在 distrobox 容器里，所有 emacs 命令必须通过 host-spawn 转发。例如： `host-..."
```

**Subagent 的"第一条 user message"是 Agent tool 的 prompt**(用户的原始问题 + 子任务背景):

```
你在 distrobox 容器里，所有 emacs 命令必须通过 host-spawn 转发。例如：
`host-spawn -no-pty emacsclient --eval '<elisp>'`

当前有个 GNU Emacs 31.0.50 daemon 在跑，用户打开了 `config.org`
（路径 `~/Projects/Config/Guix-configs/source/config.org`，72185 字节）。

## 背景
`configs/org/org-mode.el` 里有个 advice wrapper
`custom--org-src-fontify-with-read-only-inhibited`，包在
`org-src-font-lock-fontify-block` 上。它做三件事：
1. **scheme 跳过**：...
```

→ 它的语义 = "用户原始问题 + parent session 的上下文摘录",应作为 subagent session 的第一条 user message 正常渲染。

**Importer 策略:**

- 扁平导入:把 subagent title 作为 marker(`## Subagent: <title>`)嵌在调用 Agent tool 的 part 附近
- 层级导入:subagent session 单独作为一颗树

---

## 11. 目标 session sanity check

目标 `sess_6a94a941-...` 是**真实的调试对话**,内容如下:

### 第一条 user(slash command)

```
Run custom command /distrobox.
Command source: user/zcode.

## 运行环境：distrobox 容器（硬约束）
... [distrobox / host-spawn 环境约束, 2312 chars]
```

### 第二条 user(真实任务)

```
目前打开org文件的时候会频繁报错，并且现在代码段不能够正常染色，也不会显示背景，
我将我目前看到的报错给你看看，你看看该怎么修复。注意：我修改了仓库的配置，
emacs目前由stow管理，所以你只需要重启emacs-daemon即可，记得更新AGENTS.md

pixel-scroll-precision-scroll-up: Beginning of buffer
Native code fontification error in #<buffer config.org> at pos33149
 Error: "  backtrace-to-string(nil)
  #f(compiled-function (lang start end) ... (#("js" 0 2 (fontified t)) 33149 33700)
  ...
"   [完整 stack trace ~50 行]
Error running timer 'indent-bars--update-current-depth-highlight-in-buffer': (arith-error)
```

### 最后一条 user

```
别开分支，直接commit到main
```

### 最后一条 assistant(parts: step-start + text + step-finish)

```
已提交到 main 分支：

**`6ce83d1` FIX: org 代码块不染色 + indent-bars arith-error timer**

- `configs/editor/navigation.el`: +indent-bars guard（+17 行）
- `configs/org/org-mode.el`: 删除错误的 wrapper（-53 行）

工作区干净，无残留改动。
```

→ **Importer 跑这个 session 能拿到真实对话**(从 distrobox 环境约束 → org bug 报告 → 调试 → 修复 → 提交),不是空对话。✓

---

## 12. 字段映射 cheat sheet(给 importer 直接抄)

| hermes / 目标字段              | zcode 来源                                                             | 取值                                                              |
| ------------------------------ | ---------------------------------------------------------------------- | ----------------------------------------------------------------- |
| session.id                     | session.id                                                             | `sess_<uuid>` 或 `sess_subagent_agent_<uuid>`                     |
| session.title                  | session.title                                                          | 字符串;`title_source ∈ {default, first_input, generated, custom}` |
| session.cwd                    | session.directory                                                      | **用这个**,比 message.contextSnapshot.envInfo.cwd 稳定            |
| session.parent_id              | session.parent_id                                                      | NULL=root;subagent child 的 parent 是 parent session id           |
| session.task_type              | session.task_type                                                      | `interactive` / `subagent_child`                                  |
| session.created_at             | session.time_created                                                   | **ms**;除以 1000 才是秒                                           |
| session.updated_at             | session.time_updated                                                   | ms                                                                |
| message.role                   | json_extract(message.data,'$.role')                                    | `user` / `assistant`(**无 system**)                               |
| message.created_at             | message.time_created                                                   | ms                                                                |
| message.parent_message_id      | json_extract(assistant.data,'$.parentID')                              | assistant→user;user→上一条 assistant(从列表推)                    |
| message.model                  | json_extract(data,'$.modelID') 或 json_extract(data,'$.model.modelID') | 如 `GLM-5.2`                                                      |
| message.mode                   | json_extract(data,'$.mode')                                            | `build` / `yolo`                                                  |
| message.finish                 | json_extract(data,'$.finish')                                          | `stop` 等                                                         |
| message.tokens                 | json_extract(data,'$.tokens')                                          | total/input/output/reasoning/cache.read/cache.write               |
| text content                   | part where type='text', json_extract(data,'$.text')                    | 合并所有 text part(顺序按 part.id 或 part.time_created)           |
| synthetic marker               | json_extract(part.data,'$.synthetic')                                  | true → 是系统注入,折叠或归到 system 角色                          |
| reasoning content              | part where type='reasoning', json_extract(data,'$.text')               | hermes 的 thinking 块                                             |
| **tool call (single source!)** | **part where type='tool'**                                             | `{callID, tool, state:{status, input, output, time, metadata}}`   |
| tool input                     | json_extract(part.data,'$.state.input')                                | JSON object                                                       |
| tool output                    | json_extract(part.data,'$.state.output')                               | string                                                            |
| tool name                      | json_extract(part.data,'$.tool')                                       | `Read` / `Bash` / `Skill` / `Agent` / ...                         |
| tool call id                   | json_extract(part.data,'$.callID')                                     | `call_<hex>`                                                      |
| tool duration                  | json_extract(part.data,'$.state.time')                                 | `{start, end}` ms                                                 |
| compaction event               | part where type='compaction'                                           | 见 §3.6                                                           |
| file attachment                | part where type='file'                                                 | 仅 7 条全局;附在 user message                                     |
| env metadata                   | json_extract(user.data,'$.contextSnapshot.envInfo')                    | **per-turn snapshot**,建议只用于 metadata,不写 content            |
| step markers                   | part where type='step-start' / 'step-finish'                           | 标记 turn 边界,可作 UI 折叠点                                     |

---

## 13. 其它表(importer 可选消费)

| 表                                                                                          | 用途                                                          | 是否需要                 |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------ |
| `session_entry`                                                                             | runtime events,本库只有 `runtime/bash_shell_selection`(57 条) | 暂不需要                 |
| `session_target`                                                                            | session 的目标/预算/objective/status                          | 可选 metadata            |
| `todo`                                                                                      | session 内的 todo 列表(content/status/priority/position)      | 可作为结构化摘要         |
| `tool_usage`                                                                                | 工具调用的运行时统计(duration_ms, exit_code, retry_count 等)  | 可选做"详细工具耗时"面板 |
| `turn_usage`                                                                                | turn 级 token 统计(input/output/reasoning/cache/TTFT)         | 可选做 token 时间线      |
| `model_usage`                                                                               | model call 级统计(latency、provider metadata)                 | 可选                     |
| `workflow_run` / `workflow_definition` / `workflow_event` / `workflow_activity`             | 内部 workflow 引擎,**与对话 importer 无关**                   | 不要碰                   |
| `input_history` / `local_setting` / `permission` / `schema_migration` / `session_task_link` | 客户端配置与 schema 迁移记录                                  | 不要碰                   |

---

## 14. 验证清单 ✓

| 问题                                          | 回答                                                                                                                                                 |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. message.data.role 的所有取值               | `user` / `assistant`(无 system)                                                                                                                      |
| 2. part.data.type 的所有取值 + 字段形状       | tool / step-start / step-finish / text / reasoning / compaction / file — 见 §3                                                                       |
| 3. assistant tool call 怎么存                 | **单独 part,type=tool**;callID=`call_<hex>`;input 是 JSON 对象、output 是字符串                                                                      |
| 4. user message 的 text part 是全部内容吗     | 是(33/34 是单 text;唯一例外是 /compact 续接,含 text + compaction)                                                                                    |
| 5. system message 长什么样                    | 没有 system role;自动注入是 user message + `synthetic:true` 的 text part                                                                             |
| 6. time_created 单位                          | **毫秒 ms since epoch**(已用 datetime() 验证 = 2026-06-23 15:36:54,delta=10ms)                                                                       |
| 7. message.data.tool_calls 顶层字段           | **始终 NULL**;part.type="tool" 是唯一 source of truth                                                                                                |
| 8. subagent user message 内容                 | Agent tool 的 prompt(用户原始问题 + 子任务背景)                                                                                                      |
| 9. envInfo 应作为 session 还是 message 元数据 | **per-turn snapshot**(cwd 会变),用 session.directory 做 session 级 cwd;envInfo 只做 metadata                                                         |
| 10. 目标 session 内容 sanity                  | ✓ 第一条 = `/distrobox` 环境约束(真实输入),第二条 = 真实 org bug 任务,最后一条 = "别开分支,直接commit到main" / 助手回复 "已提交 6ce83d1"。可正常导入 |
