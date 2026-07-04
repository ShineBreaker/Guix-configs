# zcode → hermes (worked example)

End-to-end-verified importer for zcode (an OpenCode-architecture
fork). Verified on the 2026-07-04 install against a 375-message
session (sess_6a94a941), all four verify probes passed.

**Source of truth:** `~/.zcode/cli/db/db.sqlite` (SQLite)
**Derived, ignore for import:** `~/.zcode/cli/rollout/*.jsonl`
**Implements:** `../scripts/import-zcode-to-hermes.py` (shipped with
this skill — keeps the importer co-located with the docs that
describe it, so backing up the skill is enough to keep the
working tooling).

## What this file covers

1. Layout and the rollout-jsonl trap
2. SQLite schema (the three core tables)
3. `message.data` and `part.data` per-type shapes — what the importer
   actually reads, with the field names that match the on-disk JSON
4. Worked importer script (full, runnable)
5. Verify probes (the four from SKILL.md applied to zcode)
6. Pitfalls observed during the 2026-07-04 session

For the high-level flow (SessionDB API, idempotency, conventions,
the four probes) see `../SKILL.md`. This file only documents
zcode-specific knowledge.

---

## 1. Layout

```bash
~/.zcode/
├── cli/
│   ├── db/db.sqlite                # ← source of truth (read this)
│   ├── rollout/model-io-sess_*.jsonl  # ← derived, per-API-call mirror (IGNORE)
│   ├── artifacts/sess_*/call_*-tool-result-*.json  # tool result blobs
│   ├── plugins/                    # zcode's plugin sandbox
│   └── log/zcode-YYYY-MM-DD.jsonl  # runtime log
└── v2/                             # config + cache; not relevant for import
```

**The rollout/*.jsonl trap.** It looks like a transcript and has
100+ lines per session, but on closer inspection every line is one
API call:

- `request.body.messages` is `[]` (only `system` content lives there)
- `response` is a flat `{text, toolCalls:[{id,name,input}], finishReason}`
  — no `role`, no content blocks, often no `thinking` persisted
- `request.messageCount` / `request.messageOffset` are the only
  hint that the **true session content lives in the SQLite DB**
  elsewhere

If you find yourself writing a JSONL importer against zcode, stop —
you missed the SQLite store. ~5 hours of debugging avoided.

---

## 2. SQLite schema (the three core tables)

```sql
CREATE TABLE session (
  id text primary key,
  project_id text not null,
  workspace_id text, parent_id text,         -- parent_id set on subagent
  slug text not null,
  directory text not null,                    -- ← use this for hermes.cwd
  path text,                                 -- sometimes a git worktree; ignore
  title text not null,                        -- ← use this for hermes.title
  version text not null,
  share_url text, summary_*, revert, permission text,
  time_created integer not null,              -- ms since epoch
  time_updated integer not null,              -- ms since epoch
  time_compacting integer, time_archived integer,
  task_type text not null default 'interactive',  -- 'interactive' | 'subagent_child'
  title_source, title_message_id, time_title_updated, trace_id
);

CREATE TABLE message (
  id text primary key,
  session_id text not null references session(id) on delete cascade,
  time_created integer not null,              -- ms since epoch
  time_updated integer not null,
  data text not null                          -- JSON
);

CREATE TABLE part (
  id text primary key,
  message_id text not null references message(id) on delete cascade,
  session_id text not null,
  time_created integer not null,              -- ms since epoch
  time_updated integer not null,
  data text not null                          -- JSON, see §3
);
```

Other tables (`todo`, `turn_usage`, `model_usage`, `tool_usage`,
`session_target`, `permission`, `input_history`, `workflow_*`,
`schema_migration`) are not needed for transcript import.

**`message.data.role` values** (verified on 6768 messages across the
full corpus): only `user` and `assistant`. **No `role=system`**
top-level messages exist; auto-injected system reminders (TodoWrite
nudges, skill hints) appear as `user` messages whose text parts have
`synthetic: true` (see §3.1).

**Time unit:** all `time_*` fields are **milliseconds since epoch**
(`Date.now()` style). Anything `> 1e12` is ms; anything `≤ 1e12` is
seconds. Coercion: `v / 1000.0 if v > 1e12 else float(v)`.

---

## 3. JSON shapes

### 3.1 `message.data` (top-level)

```jsonc
{
  "role": "user" | "assistant",
  "time": { "created": 1782229014686, "completed": 1782229025330 },
  "agent": "zcode-agent",
  "model": {
    "providerID": "builtin:bigmodel-coding-plan",
    "modelID": "GLM-5.2"
  },
  "contextSnapshot": {            // user message only — env snapshot
    "envInfo": {
      "cwd": "...", "platform": "linux", "shell": "fish",
      "gitBranch": "main", "gitStatus": "clean",
      "recentCommits": ["8a0f6c5 FIX: ...", "..."]
    }
  },
  "tools": { "Read": true, "Write": true, "Bash": true, "Agent": true, "Skill": true, "...": true },
  "parentID": "msg_...",            // assistant only: previous user message
  "mode": "build" | "yolo",
  "cost": 0,
  "tokens": { "total": ..., "input": ..., "output": ..., "cache": {"read": ..., "write": ...} },
  "finish": "stop" | "tool-calls" | "aborted"  // assistant only
}
```

For hermes:
- `model.modelID` → `create_session(model=...)`
- `model.providerID` → `create_session(model_config={"provider": ...})`
- `session.directory` → `create_session(cwd=...)` (more stable than
  `contextSnapshot.envInfo.cwd`, which is per-turn)
- `envInfo` itself → don't write into `messages.content`; use as
  hermes session metadata only

### 3.2 `part.data` per-type field shapes (verified)

| `data.type`     | key fields                                                                 | hermes mapping                                                                                  |
| --------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `text`          | `text` (string), `time.start`, `time.end`, `synthetic` (bool, user only) | join into `content` (assistant/user) or `reasoning_content`; synthetic → fold to marker        |
| `reasoning`     | `text` (string), `time.start`, `time.end`                                 | join into `reasoning_content`                                                                   |
| `tool`          | `callID` (string `call_<hex>`), `tool` (string), `state.{status,input,output,time,metadata}` | emits OpenAI-style `tool_calls` on assistant + paired `tool` row (see §3.3)                    |
| `step-start`    | (no content)                                                              | turn boundary marker — emit nothing                                                              |
| `step-finish`   | `reason: "stop"\|"tool-calls"\|"aborted"\|"error"`, `cost`, `tokens`       | `reason` → `finish_reason` on the assistant row                                                  |
| `compaction`    | `auto`, `trigger`, `phase`, `compactBoundary.*`                           | skip (the model-side summary is the post-compaction user message; the part is metadata)         |
| `file`          | `mime`, `filename`, `url: "zcode-artifact://..."`, `source.path`, `metadata.{width,height,storageKind,artifactUri}` | render as `[attachment: <filename>]` stub (zcode-artifact URLs are not http-fetchable)         |

**Order parts within a message by** `part.time_created, part.id`.

#### 3.3 `part.data` for `type=tool` (the source of truth)

Verified sample (Grep tool):

```jsonc
{
  "type": "tool",
  "callID": "call_ca17d1d7e82746b087158f2c",   // ← tool_call_id
  "tool": "Grep",                              // ← tool_name
  "state": {
    "status": "completed",                      // "running" | "error" | "cancelled"
    "input":  {"pattern": "indent-bars", "output_mode": "files_with_matches"},
    "output": "Found 3 files\ndiagnose/test-config-loading.el\n...",
    "title":  "Grep",
    "metadata": {
      "schemaVersion": 1,
      "serialization": {"truncated": false, "originalBytes": 85, "returnedBytes": 85, "budgetStrategy": "artifact"}
    },
    "time": { "start": 1782229384806, "end": 1782229384919 }   // ms epoch
  }
}
```

**`callID` is the tool_call_id** (note: not `part.id`, not
`part.data.id`). Pair `tool` rows in hermes to the parent
assistant's `tool_calls[].id` on this field. Namespace is
`call_<24-28 hex>` (not Anthropic `toolu_xxx`, not OpenAI's shorter
`call_xxxxxxxx`).

**`state.input` is a JSON object**, even for Bash — it's
`{"command": "...", "description": "..."}`, not a string. Convert
to a JSON string for OpenAI-style `tool_calls[].function.arguments`.

**`state.output` is a string**, can be very large. Truncate to
~50 KB with a `[... truncated by importer ...]` suffix (see §6.4).

**`message.data.tool_calls` is always NULL** on the message top
level. `part.type=tool` is the **only** source of tool calls.
Verified on the full corpus: 6768/6768 messages have
`json_extract(message.data, '$.tool_calls') IS NULL`. (Note: when
querying both tables in one statement, fully qualify
`message.data` vs `part.data` to avoid the `ambiguous column
name: data` parse error SQLite throws.)

### 3.4 Subagent sessions

`session.id LIKE 'sess_subagent_agent_%'` and `session.parent_id`
is set to the parent session's id. Filter with
`session.id NOT LIKE 'sess_subagent_agent_%'` for parent sessions
only. Subagent's first `message.role='user'` is the Task tool's
prompt (the parent's task brief), not a real user typing — keep
with `[subagent]` title prefix if you import it.

---

## 4. Worked importer script

Full, end-to-end-verified, idempotent. Re-execs under the nix-store
hermes python venv on first non-dry-run call. The venv is
auto-discovered by `_resolve_hermes_py()` (preferring the candidate
whose `hermes_constants.get_hermes_home()` matches the current
user's `$HERMES_HOME`); override with `$HERMES_AGENT_PY` for
non-Nix installs.

Locations:

- Script: `../scripts/import-zcode-to-hermes.py` (ships with the
  skill)
- Backup / sync: copy the script somewhere on `$PATH` if you
  want to call it without the relative prefix

Modes:

```bash
../scripts/import-zcode-to-hermes.py --list                        # list all sessions
../scripts/import-zcode-to-hermes.py --dry-run <session-id>        # plan, no writes
../scripts/import-zcode-to-hermes.py <session-id>                  # import one
../scripts/import-zcode-to-hermes.py --all-parents                 # import all 31
                                                                 #   interactive sessions
                                                                 #   (skips already-imported)
```

The `--list` and `--dry-run` paths stay under the user python
(no `hermes_state` import, no re-exec) so they work in any shell.

### Key design decisions (read this before editing the script)

1. **Re-exec pattern.** When the user python is current and not
   in dry-run/list mode, the script `os.execvp`s itself under
   `/nix/store/<hash>-hermes-agent-env/bin/python3` so that
   `from hermes_state import SessionDB` succeeds. The hash on
   your host may differ; find yours with:
   `ls /nix/store/*-hermes-agent-env/bin/python3`.

2. **Idempotency guard is `if db is not None and db.get_session(...)
   then skip`.** The `db is not None` is required because dry-run
   passes `None` for `db` (no hermes import) — the guard crashes
   on `None.get_session(...)` otherwise. (Patched bug from a
   first dry-run that hit `AttributeError: 'NoneType' object has
   no attribute 'get_session'`.)

3. **Synthetic user text fold.** When `part.data.synthetic == true`,
   the first line (truncated to 120 chars) is rendered as
   `[system-reminder] <first line>`. The full text is not inlined
   because on resume the LLM misreads it as something the user
   "said" — verified quality drop on sess_6a94a941.

4. **Tool result emission is post-hoc.** For each assistant message
   with `tool_calls`, after writing the assistant row, walk the
   same part list and emit one `tool` row per `part.type='tool'`,
   carrying `tool_call_id = part.callID`, `tool_name = part.tool`,
   `content = part.state.output` (truncated to 50 KB).

5. **end_session safety.** `end_session()` only updates `ended_at`
   when it's NULL. The script does a raw SQL
   `UPDATE sessions SET started_at=?, ended_at=?, title=?,
   end_reason=?` first, then **calls `end_session` only if
   `ended_at IS NULL`** — otherwise the second call no-ops and
   `end_reason` ends up as `"imported-imported-zcode"` (double
   prefix). This was a real bug observed on the first run.

6. **Strict monotonicity per session.** Each emitted timestamp is
   `max(prev_ts + 1ms, parsed_zcode_ts)`. Hermes orders messages
   by autoincrement id, but `timestamp` is denormalized into many
   surfaces (UI sort, `session_search` snippets) and out-of-order
   stamps confuse both.

7. **Time floor = `session.time_created / 1000.0`.** The first
   message's `time_created` may differ from `session.time_created`
   by a few ms; pinning to the session time guarantees every
   emitted row sorts after `sessions.started_at`.

---

## 5. Verify probes (zcode-specific application)

```bash
HERMES_AGENT_PY="/nix/store/8ffp1jjm06v9khlf0h4wgjbihqnm61di-hermes-agent-env/bin/python3"  # or auto-discovered
SID="<session_id>"

# 1) row counts vs zcode's count
echo "  zcode:"
sqlite3 ~/.zcode/cli/db/db.sqlite \
  "SELECT json_extract(data,'\$.role') AS role, COUNT(*) FROM message
    WHERE session_id='$SID' GROUP BY role;"
echo "  zcode tool parts:"
sqlite3 ~/.zcode/cli/db/db.sqlite \
  "SELECT COUNT(*) FROM part p JOIN message m ON p.message_id=m.id
    WHERE m.session_id='$SID' AND json_extract(p.data,'\$.type')='tool';"
echo "  hermes:"
sqlite3 ~/.local/share/hermes/state.db \
  "SELECT role, COUNT(*) FROM messages WHERE session_id='$SID' GROUP BY role;"

# 2) tool-call pairing — every tool row must have a non-null tool_call_id
sqlite3 ~/.local/share/hermes/state.db \
  "SELECT
     SUM(CASE WHEN role='tool' AND tool_call_id IS NOT NULL THEN 1 ELSE 0 END) AS paired,
     SUM(CASE WHEN role='tool' THEN 1 ELSE 0 END) AS total_tool_rows,
     SUM(CASE WHEN role='assistant' AND tool_calls IS NOT NULL AND tool_calls != 'null' THEN 1 ELSE 0 END) AS assistant_with_tools
   FROM messages WHERE session_id='$SID';"

# 3) round-trip
"$HERMES_AGENT_PY" -c "
from hermes_state import SessionDB
msgs = SessionDB().get_messages_as_conversation('$SID')
for m in msgs[:3]: print(m['role'], str(m.get('content',''))[:80])
print('...')
for m in msgs[-3:]: print(m['role'], str(m.get('content',''))[:80])
print('total:', len(msgs))
"

# 4) live resume — short timeout; you're checking loadability, not
#    waiting for an answer
timeout 30 hermes chat --resume "$SID" -q "续"
```

If step 4 errors instead of firing a tool call or model response,
suspect (in order of likelihood):

- `content=None` instead of `""` on a tool-only assistant row →
  fix `build_assistant_payload` to default to `""`
- timestamps out of order → check `_ms_to_s` ms-vs-seconds
  detection
- `callID` is missing on a tool part → fall back to
  `f"imported-zcode-{part.id}"` (synthetic but still unique)
- synthetic system reminders inlined as user rows → re-check
  `synthetic: true` fold

---

## 6. Pitfalls observed on the 2026-07-04 sample

1. **`rollout/*.jsonl` is a trap** (§1). Don't waste time writing
   a JSONL importer; go straight to the DB.

2. **Millisecond timestamps** (§2). `v / 1000.0 if v > 1e12 else
   float(v)`. Hermes uses seconds, so the value comparison
   threshold is the only safe way to distinguish them.

3. **No `role=system` rows.** zcode treats the first user message
   as a normal `user` row; the env snapshot (cwd/git/recent
   commits) lives in `message.data.contextSnapshot` rather than
   as a separate system row. Use `session.directory` for the
   hermes session-level `cwd` (stable across the session);
   `contextSnapshot.envInfo.cwd` is per-turn and can change.

4. **Tool rows are never top-level rows.** Tool inputs/outputs
   always appear as `part.type='tool'` children of an assistant
   message. There's no `role='tool'` in zcode's data — your
   importer never has to handle that case.

5. **`message.data.tool_calls` is always NULL.** Don't try to
   pull tool calls from the message top level; they only exist
   on parts. (SQL: 6768/6768 messages have
   `json_extract(data, '$.tool_calls') IS NULL`.)

6. **`reasoning` may be absent even when `thinking` was enabled.**
   The provider can return content without `thinking` blocks;
   the SQLite part tree reflects what was returned, not what
   was requested. Empty `reasoning_content` is fine — don't
   synthesize filler.

7. **`step-start` / `step-finish` parts carry no payload** (just
   `reason` and token stats on `step-finish`). Treat them as
   turn-coalescing markers. `step-finish.reason` is the closest
   analog to hermes's `finish_reason`.

8. **`directory` ≠ `path`.** `session.directory` is the cwd;
   `session.path` is sometimes null and sometimes a git worktree
   path. Use `directory` for `cwd`.

9. **Subagent sessions are full sessions.** Don't skip them
   silently; either include with `--include-subagents` (the
   current importer skips them; the flag is a TODO) or note
   them in the recap. Their first user message is the parent's
   task brief, not a real user typing — prefix the imported
   title with `[subagent]` if you keep them.

10. **Synthetic user text is system chatter, not user intent.**
    Auto-injected TodoWrite reminders and skill hints land as
    `role='user'` rows whose text parts have `synthetic: true`.
    They pollute the conversation stream on resume (the LLM
    sees the system reminder as something the user "said").
    Fold to a one-line marker (e.g. `[system-reminder] <first
    line>`) instead of inlining the full text. Verified
    pitfall on sess_6a94a941 — leaving synthetic text in
    visibly dropped live-resume quality.

11. **Truncate long tool outputs.** A single `Bash` tool can
    return hundreds of KB (large `cat`, `find`, `grep -r`).
    Storing the full text in `messages.content` bloats
    `state.db` and slows FTS indexing. Cap at ~50 KB with a
    `[... truncated by importer ...]` suffix; the LLM on
    resume can re-run the tool if it needs more.

12. **Backup before first import.**
    `cp ~/.local/share/hermes/state.db{,.pre-zcode-import.bak}`
    is cheap and reversible. If the importer writes a row the
    gateway chokes on, recovery is one `cp` away.
