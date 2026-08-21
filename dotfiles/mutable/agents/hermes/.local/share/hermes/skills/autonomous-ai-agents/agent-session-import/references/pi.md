# pi → hermes (worked example)

`pi` is an agentic coding CLI/TUI whose session transcripts live at
`~/.local/share/pi/sessions/*.jsonl`. One session per file, named
`<ISO timestamp>_<uuid>.jsonl`; the uuid matches the in-file
`type:"session".id` 100% of the time on observed installs (245 / 245).

## Event types

| type | meaning | importer action |
|------|---------|-----------------|
| `session` | header (first line) | source for `cwd`, `started_at`, `id` |
| `thinking_level_change` | metadata only | skip |
| `model_change` | metadata, but updates the `model` / `provider` recorded for the session | track for `sessions.model` / `model_config` |
| `custom` / `custom_message` | UI state, no conversation content | skip |
| `compaction` | context-compaction marker | skip |
| `message` | the actual conversation | translate per `message.role` |

## Message shape (pi version 3)

`message.content` is almost always a **list of typed blocks**, not a
string. Block types observed: `text`, `thinking`, `toolCall`, `image`.

```jsonc
{
  "role": "assistant",
  "content": [
    {"type": "thinking", "thinking": "...", "thinkingSignature": "reasoning_content"},
    {"type": "toolCall", "id": "functions.fffind:0", "name": "fffind", "arguments": {"pattern": "..."}},
    {"type": "text", "text": "..."}
  ],
  "api": "openai-completions",
  "provider": "opencode-go",
  "model": "kimi-k2.6",
  "usage": {"input": ..., "output": ..., "cacheRead": ..., "cacheWrite": ..., "cost": {...}},
  "stopReason": "toolUse" | "stop" | "aborted" | "error",
  "timestamp": "2026-05-21T05:26:17.885Z",
  "responseId": "chatcmpl-...",
  "responseModel": "accounts/fireworks/models/kimi-k2p6"
}
```

## Role translation

| pi role | hermes role | extras |
|---------|-------------|--------|
| `user` | `user` | `content` from text/image blocks; `_split_user_content` joins text, keeps image blocks for multimodal list-of-parts |
| `assistant` | `assistant` (may need turn-coalescing) | `text` blocks → `content`; `thinking` blocks → `reasoning_content` joined with `\n\n`; `toolCall` blocks → OpenAI-style `tool_calls` list `{id, type:"function", function:{name, arguments}}` |
| `toolResult` | `tool` | `tool_call_id = message.toolCallId`; `tool_name = message.toolName`; `content = flattened toolResult text` |

Non-standard `role` values pi has shipped over time (e.g.
`bashExecution`) are normalized to `tool` with a synthesized
`tool_name` inside the importer — see `import-pi-to-hermes.py`
for the dispatch table.

| `image` blocks: leave the full block dict in the part-list and let
hermes's `_encode_content` JSON-serialize it with the `\x00json:`
prefix. We don't decode base64 on import.

## ToolCall id pairing

Every pi `toolResult.toolCallId` corresponds to a `toolCall.id` of the
form `functions.<name>:<n>`. Verified on the test corpus: 14 toolCall
ids ⇄ 14 toolResult ids, all unique, all paired. The importer stores
these as `tool_call_id` directly on the `tool` row; hermes doesn't
require cross-table linkage, only the textual id on the tool row.

## Turn-coalescing

In the test corpus (245 sessions, ~23k assistant events):

- 226 sessions: every assistant turn is a single message event → no merging needed.
- 5 sessions have one 2-segment split per session.
- 1 session has a 4-segment split.
- Total: 31 runs across the corpus.

A "run" is consecutive `role:"assistant"` message events with no
`user` / `tool` between them. Importer must accumulate `text +
thinking + tool_calls + images + finish_reason` across the run and
emit one merged `assistant` row. Use the timestamp of the first
segment in the run as the merged row's timestamp; record the run's
`stopReason` from whichever segment has it (typically the last one).

## Timestamps

All `timestamp` fields are ISO-8601 strings with trailing `Z`, e.g.
`"2026-05-21T05:26:17.885Z"`. Parse with:

```python
from datetime import datetime, timezone
dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
return dt.timestamp()
```

Defensive variant that also accepts millisecond floats (in case the
schema ever changes): `v / 1000.0 if v > 1e12 else float(v)`.

## Title derivation

`title = first_user_text[:60] + ("…" if longer else "")` where
`first_user_text` is the first `user` message's joined text blocks
across the whole session. Fallback: the pi uuid.

## Working importer

`../scripts/import-pi-to-hermes.py` (shipped with this skill;
1100+ lines). The high-level flow (idempotency guard, turn-coalescing
walk, raw-SQL backfill of `started_at / ended_at / title`,
re-exec-under-hermes-python) is documented in `../SKILL.md`; this
file is the place to look for the pi-specific translation tables
above. Usage:

```bash
../scripts/import-pi-to-hermes.py --dry-run <file>.jsonl   # plan, no writes
../scripts/import-pi-to-hermes.py <file>.jsonl             # import one
../scripts/import-pi-to-hermes.py --all                    # import all
```

`--all` skips files that are already imported (idempotent on
session id). Override the nix-store venv path with
`$HERMES_AGENT_PY` if your install lives outside Nix.

## End-to-end verification (proven on a 30-msg test session)

```bash
# 1. import one file
../scripts/import-pi-to-hermes.py <file>.jsonl

# 2. row counts match expectations
sqlite3 ~/.local/share/hermes/state.db "
  SELECT role, COUNT(*) FROM messages
   WHERE session_id='<pi-uuid>' GROUP BY role;"

# 3. tool-call pairing
sqlite3 ~/.local/share/hermes/state.db "
  SELECT COUNT(*) FROM messages
   WHERE session_id='<pi-uuid>' AND role='tool' AND tool_call_id IS NOT NULL;"

# 4. hermes can load it as conversation
"$HERMES_AGENT_PY" -c "
from hermes_state import SessionDB
msgs = SessionDB().get_messages_as_conversation('<pi-uuid>')
for m in msgs: print(m['role'], m.get('content', '')[:40])"

# 5. live resume works
timeout 30 hermes chat --resume '<pi-uuid>' -q '续'
```

Steps 1–4 must all succeed before claiming victory. Step 5 is the
final gate: if hermes loop actually fires (any tool call, any model
output), the import is end-to-end correct.