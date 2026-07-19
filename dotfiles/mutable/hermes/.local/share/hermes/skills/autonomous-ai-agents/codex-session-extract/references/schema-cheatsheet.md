# Codex rollout JSONL — schema cheat sheet

Codex CLI (`codex` 0.144.x) writes each session as a single JSON-Lines
file at `~/.config/codex/sessions/YYYY/MM/DD/rollout-<ts>-<session-id>.jsonl`.
Every line is one JSON record; record types are a top-level `"type"`
field. This file is the per-record reference; for the procedural
workflow see `../SKILL.md`.

## File layout

```
~/.config/codex/sessions/
└── 2026/
    └── 07/
        └── 18/
            ├── rollout-2026-07-18T10-11-27-019f74b5-9d9f-72d1-a8b7-d227a6cf3b4c.jsonl
            └── rollout-2026-07-18T22-41-09-019f7dcc-….jsonl
```

- Filename timestamp is the **session start** in UTC (`10-11-27`), not
  local time. The path partition uses the **same UTC date**.
- A session that starts at `2026-07-18 18:11 Asia/Shanghai` (= `10:11 UTC`)
  lives under `2026/07/18/`. A session starting at `2026-07-19 02:00
  Asia/Shanghai` (= `2026-07-18 18:00 UTC`) lives under
  `2026/07/18/` — UTC partition, not local.
- `session-id` in the filename matches `session_meta.payload.session_id`
  byte-for-byte.

## Record-type histogram (observed)

```
session_meta:                                 1
turn_context:                                 ~7 per session
world_state:                                  1 per turn (often repeated)
response_item:                                ~600 per long session
  ├─ role:user                               ~10
  ├─ role:assistant                          ~200
  ├─ role:developer                          ~7
  ├─ type:function_call                      ~150
  ├─ type:function_call_output               ~150
  └─ type:custom_tool_call                   (codex 0.144+, replaces function_call for exec/apply_patch)
event_msg:                                    ~280 per long session
  ├─ task_started                            ~7
  ├─ task_complete                           ~7
  ├─ token_count                             ~250 (high-frequency)
  ├─ turn_diff                               rare
  ├─ turn_aborted                            rare
  └─ user_message                            rare
compacted:                                    0–2 per long session (only on context overflow)
inter_agent_communication_metadata:          0–4 (sub-agent signalling; content not user-facing)
```

The exact counts depend on session length, model swaps, and how many
context-window overflows happened. These ratios are the shape of a
"normal" codex session — not noise.

## Record schemas

### `session_meta` (always first)

```json
{
  "timestamp": "2026-07-18T10:13:30.031Z",
  "type": "session_meta",
  "payload": {
    "session_id": "019f74b5-9d9f-72d1-a8b7-d227a6cf3b4c",
    "id": "019f74b5-9d9f-72d1-a8b7-d227a6cf3b4c",
    "timestamp": "2026-07-18T10:11:27.272Z",
    "cwd": "/home/brokenshine/Projects/Config/Guix-configs/dotfiles/mutable/emacs/.config/emacs",
    "originator": "codex-tui",
    "cli_version": "0.144.4",
    "source": "cli",
    "thread_source": "user",
    "model_provider": "fox",
    "history_mode": "legacy",
    "context_window": { "window_id": "…" },
    "git": {
      "commit_hash": "24dae51487fea7984d370f0844ee790a9ee6cbf3",
      "branch": "main",
      "repository_url": "https://codeberg.org/BrokenShine/Guix-configs.git"
    },
    "base_instructions": { "text": "…16 KB system prompt…" }
  }
}
```

`base_instructions.text` is the Codex system prompt. 16 KB is
typical. Render at the end of the markdown, not the top.

### `turn_context`

```json
{
  "timestamp": "2026-07-18T10:13:30.034Z",
  "type": "turn_context",
  "payload": {
    "turn_id": "019f74b7-7cde-7233-aec7-288900885096",
    "model": "gpt-5.6-sol",          ← can swap mid-session
    "effort": "xhigh",               ← "xhigh" or "high"
    "personality": "pragmatic",
    "cwd": "…",
    "workspace_roots": ["…"],
    "approval_policy": "on-request",
    "approvals_reviewer": "user",
    "sandbox_policy": { "type": "workspace-write", "network_access": false, … },
    "permission_profile": { … },
    "collaboration_mode": "Default",
    "multi_agent_mode": "explicitRequestOnly",
    "summary": "auto"
  }
}
```

A new `turn_context` = a new "Turn N" subsection in the markdown.
Model can swap; preserve per-turn.

### `world_state`

```json
{
  "timestamp": "…",
  "type": "world_state",
  "payload": {
    "full": true,
    "state": {
      "agents_md": {
        "directory": "/…/emacs/.config/emacs",
        "text": "# Guix-configs — 仓库导引\n…"
      }
    }
  }
}
```

The model receives the project's `AGENTS.md` (or equivalent) on every
turn. The text is typically identical turn-over-turn, but codex may
re-emit it when the file changes or when entering a new directory.

### `response_item` — message

```json
{
  "type": "response_item",
  "payload": {
    "type": "message",
    "role": "assistant",
    "content": [
      { "type": "text", "text": "I'll grill the user…" },
      { "type": "reasoning", "encrypted_content": "gAAAAA…", "summary": [] }
    ]
  }
}
```

`content[]` can mix `text`, `reasoning`, `function_call`, and
`function_call_output`. Render in arrival order.

### `response_item` — function_call / function_call_output

```json
{
  "type": "response_item",
  "payload": {
    "type": "function_call",
    "name": "exec_command",
    "arguments": "{\"cmd\":\"ls -la\"}",       ← JSON-encoded string
    "call_id": "call_1oVWemf83pQebWLzKkFK4Q6p"
  }
}
```

```json
{
  "type": "response_item",
  "payload": {
    "type": "function_call_output",
    "call_id": "call_1oVWemf83pQebWLzKkFK4Q6p",
    "output": "total 12\n…"                 ← OR list of content blocks
  }
}
```

`function_call_output.output` is **string in older codex**, **list of
content blocks in newer codex**:

```json
{
  "output": [
    {"type": "input_text", "text": "Script completed\n"},
    {"type": "input_text", "text": "Output:\n---…"}
  ]
}
```

The script in `scripts/codex_extract.py` normalises both.

### `response_item` — custom_tool_call (codex 0.144+)

```json
{
  "type": "response_item",
  "payload": {
    "type": "custom_tool_call",
    "id": "ctc_04f11f185a…",
    "status": "completed",
    "call_id": "call_1oVWemf83pQebWLzKkFK4Q6p",
    "name": "exec",
    "input": "const r = await tools.exec_command({\"cmd\":\"ls -la\",\"workdir\":\"/tmp\",\"yield_time_ms\":10000});\ntext(r.output);"
  }
}
```

Codex 0.144 renamed `function_call` → `custom_tool_call` for native
tools (`exec`, `apply_patch`, etc.). The schema differs in two ways:

1. **`input` is a JavaScript shim**, not a JSON string. The script
   `extract_json_from_shim(input)` (regex `r'await\s+tools\.(\w+)\((.*)\)\s*;'`)
   extracts the JSON literal between `tools.<name>(...)`, parses it,
   and pretty-prints. If parsing fails (e.g. the shim uses a non-literal
   expression), the raw input is rendered as-is.
2. **`call_id` is the same** — `custom_tool_call.call_id` pairs with
   `custom_tool_call_output.call_id` exactly like `function_call` /
   `function_call_output`. Don't strip the `ctc_` prefix when rendering.

The tool `name` field is short (`exec`, `apply_patch`, etc.) — the
*real* tool name is in the shim (`tools.exec_command`); the script
preserves the `name` field as-given.

### `response_item` — custom_tool_call_output (codex 0.144+)

```json
{
  "type": "response_item",
  "payload": {
    "type": "custom_tool_call_output",
    "call_id": "call_1oVWemf83pQebWLzKkFK4Q6p",
    "output": [
      {"type": "input_text", "text": "Script completed\nWall time 0.1s\nOutput:\n"},
      {"type": "input_text", "text": "total 12\n…"}
    ]
  }
}
```

`output` is **always a list of content blocks** in 0.144+. Block types
seen in the wild:

| Block `type`            | Content shape                              | Script handling                            |
| ----------------------- | ------------------------------------------ | ------------------------------------------ |
| `input_text`            | `{ "text": "..." }`                        | Concatenate into normalised text           |
| `agent_message`         | `{ "author": "/root/X", "content": [...] }` | Concatenate plaintext `input_text` parts only; drop if all parts are `encrypted_content` |
| `encrypted_content`     | `{ "encrypted_content": "gAAAAA…" }`       | Drop (chain-of-thought is e2e-encrypted)   |

The plaintext `agent_message` payloads (e.g. `FINAL_ANSWER` from a
`/root/spec_review` sub-agent) ARE meaningful — they contain the
sub-agent's actual report. Don't drop them just because the block is
`agent_message`; drop only when the inner `content[]` has zero
`input_text` parts.

### `response_item` — reasoning (top-level)

```json
{
  "type": "response_item",
  "payload": {
    "type": "reasoning",
    "id": "rs_04f11f185a…",
    "summary": [],
    "encrypted_content": "gAAAAA…"
  }
}
```

Top-level `reasoning` records (not nested inside a `message.content[]`)
are the **encrypted chain-of-thought stub** that codex 0.144+ writes
when no plaintext summary is available. The script's
`is_encrypted_reasoning(part)` check:

```python
def is_encrypted_reasoning(part):
    enc = part.get("encrypted_content")
    if enc and not part.get("text"):
        return True
    if not part.get("text") and not part.get("summary"):
        return True
    return False
```

treats these as droppable. If `text` is present (very rare), it IS
rendered as a `> **Reasoning**` blockquote.

## Event types — for reference, all dropped by the noise filter

> The script in `scripts/codex_extract.py` (v0.2.0+) drops **every**
> `event_msg` subtype. They appear here only so you can recognise
> them in the source jsonl — the markdown output will never show them.

### `event_msg` — task_started

```json
{ "type": "event_msg", "payload": { "type": "task_started", "turn_id": "…", "started_at": 1784369610, "model_context_window": 353400, "collaboration_mode_kind": "default" } }
```

### `event_msg` — task_complete

```json
{ "type": "event_msg", "payload": { "type": "task_complete", "turn_id": "…", "last_agent_message": "I'll start by …" } }
```

### `event_msg` — token_count

```json
{ "type": "event_msg", "payload": { "type": "token_count", "info": { "total_token_usage": { "input_tokens": 23870, "cached_input_tokens": 20992, "output_tokens": 412, "reasoning_output_tokens": 0, "total_tokens": 24282 }, "last_token_usage": { … }, "model_context_window": 353400 } } }
```

High-frequency — ~30–40 per turn on a long task. If you actually need
a token-usage log, post-process the source jsonl directly; do not
re-enable in the extractor (it dominates file size without adding
dialogue information).

### `event_msg` — turn_aborted

```json
{ "type": "event_msg", "payload": { "type": "turn_aborted", "reason": "interrupted" } }
```

Rendered only when found inside a `developer` message body (which
preserves the `<turn_aborted>...</turn_aborted>` block) — the
top-level `event_msg` form is dropped.

### `compacted`

```json
{
  "type": "compacted",
  "payload": {
    "message": "## Handoff Summary\n\n### Current Task\n…"
  }
}
```

This is a **handoff summary** Codex generates when its context window
fills up. The `message` field is the summary; render prominently.

Two compactions in a long session is normal; three+ suggests the user
kept adding tasks without offloading context.

## Field-level pitfalls

- **`model_provider` vs `model`.** `session_meta.model_provider` is the
  *provider* (e.g. `"fox"`, `"openai"`). The actual model name
  (`gpt-5.6-sol`, `gpt-5.6-luna`) is per-turn on `turn_context.model`.
- **`reasoning.encrypted_content`.** End-to-end encrypted. Cannot be
  recovered. The schema ships a `summary: []` array alongside it but
  in codex 0.144.4 it is always empty. Don't try to base64-decode it.
- **`call_id` namespace.** Codex uses `call_<24+ hex>`. Don't confuse
  with Anthropic's `toolu_…` or OpenAI's shorter `call_xxxxxxxx`.
- **Sandbox policy is on every `turn_context`, not just the first.**
  Code-switching sandbox modes mid-session is rare but possible (e.g.
  when the user approves an escalation).
- **`history_mode: "legacy"`** appears in older rollouts; newer codex
  may not include this field at all. Treat both as opaque.

## Quick verification one-liner

```bash
python3 -c "
import json
from collections import Counter
fp = '<rollout.jsonl>'
c = Counter()
with open(fp) as f:
    for line in f:
        r = json.loads(line)
        c[r.get('type')] += 1
for t, n in c.most_common():
    print(f'{t}: {n}')
"
```

Use this as a sanity check before running the full extractor — if the
counts look very different from the table at the top of this file,
the file may be from a different codex version or corrupted.