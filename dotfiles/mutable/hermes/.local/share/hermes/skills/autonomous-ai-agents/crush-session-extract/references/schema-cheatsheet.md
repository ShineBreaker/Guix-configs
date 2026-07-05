# crush schema cheat sheet

For importer authors who already know what they want — full DDL, every
observed `part.type` shape with raw samples, and a flat field-mapping table.

## 1. Source of truth

Each project keeps `<project>/.crush/crush.db`. The global file at
`~/.config/crush/.crush/crush.db` is a goose migration header and contains
**no sessions**. Walk the filesystem to find the DBs.

Confirmed on crush `v0.81.0` running on Guix System.

## 2. Table DDL (verbatim, copied from `sqlite_master`)

```sql
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    parent_session_id TEXT,
    title TEXT NOT NULL,
    message_count INTEGER NOT NULL DEFAULT 0 CHECK (message_count >= 0),
    prompt_tokens  INTEGER NOT NULL DEFAULT 0 CHECK (prompt_tokens >= 0),
    completion_tokens  INTEGER NOT NULL DEFAULT 0 CHECK (completion_tokens>= 0),
    cost REAL NOT NULL DEFAULT 0.0 CHECK (cost >= 0.0),
    updated_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    summary_message_id TEXT,
    todos TEXT
);

CREATE TABLE files (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    path TEXT NOT NULL,
    content TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE,
    UNIQUE(path, session_id, version)
);

CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    parts TEXT NOT NULL default '[]',
    model TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    finished_at INTEGER,
    provider TEXT,
    is_summary_message INTEGER DEFAULT 0 NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
);

CREATE TABLE read_files (
    session_id TEXT NOT NULL CHECK (session_id != ''),
    path TEXT NOT NULL CHECK (path != ''),
    read_at INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE,
    PRIMARY KEY (path, session_id)
);
```

Triggers (selected): `update_sessions_updated_at`,
`update_session_message_count_on_insert`,
`update_session_message_count_on_delete` — `message_count` is a derived
column maintained only by INSERT/DELETE on `messages`. A bare UPDATE bypasses
it; `verify` catches drift.

## 3. Time units (the schema lies)

DDL says: `-- Unix timestamp in milliseconds`.

Reality: stored as **seconds since epoch**. Concrete check:

```bash
sqlite3 <db> "SELECT created_at FROM sessions ORDER BY created_at DESC LIMIT 1;"
# → 1783258809   (= 2026-07-05 13:40:09 UTC, NOT 1970-something-after-/1000)
```

Always: `datetime(value, 'unixepoch', 'localtime')` works directly. Never
divide by 1000.

The `read_files.read_at` column is also seconds — same rule.

## 4. `sessions` row example

```json
{
  "id": "3783db48-79c7-4d4b-b12d-5de0c4f24c7b",
  "parent_session_id": null,
  "title": "审查过时文档和冗余大型表格",
  "message_count": 184,
  "prompt_tokens": 104688,
  "completion_tokens": 498,
  "cost": 0.0771,
  "created_at": 1783258809,
  "updated_at": 1783259515,
  "summary_message_id": null,
  "todos": null
}
```

## 5. `messages.parts` JSON shape — every observed type

`parts` is a JSON TEXT array. A single assistant message may contain
several parts in this order: `[reasoning?, text?, tool_call* (paired with
tool_result in the next message?), finish?]`. The user role is almost always
`[text, finish]`.

### `text` — user / assistant utterance

```json
{"type":"text","data":{"text":"帮我审查一下仓库中有没有过时的文档..."}}
```

### `finish` — terminator at the end of each message

```json
{"type":"finish","data":{"reason":"stop","time":0}}
{"type":"finish","data":{"reason":"tool_use","time":1783258913}}
```

`reason` values seen so far: `stop`, `tool_use`, `length`,
`content_filter`. `time` is **seconds since message start**, not ms (and
distinct from `messages.finished_at`).

### `reasoning` — chain-of-thought (Anthropic / OpenAI o-series style)

```json
{
  "type":"reasoning",
  "data":{
    "thinking":"用户要我审查仓库...",
    "signature":"",
    "thought_signature":"",
    "tool_id":"",
    "responses_data":null,
    "started_at":1783258815,
    "finished_at":1783258816
  }
}
```

`started_at` / `finished_at` are seconds (same rule as `created_at`).
`thinking` may be empty string when the model emitted no reasoning.

### `tool_call` — model asking to invoke a tool

```json
{
  "type":"tool_call",
  "data":{
    "id":"call_1a0343e6c98c19fa",
    "name":"agent",
    "input":"{\"prompt\": \"搜索 ...\"}",
    "provider_executed":false,
    "finished":true
  }
}
```

**`input` is a JSON STRING, not an object.** Always `json.loads()` before
reading nested fields. `id` and `name` are tool_call_id / tool name (e.g.
`agent`, `grep`, `read`, `write`, `bash`, `edit`).

### `tool_result` — paired with the previous assistant's tool_call

Stored in the **next message** (role=`tool`), not the same message as the
tool_call. The pairing key is `data.tool_call_id == previous tool_call.data.id`.

```json
{
  "type":"tool_result",
  "data":{
    "tool_call_id":"call_e38c7bb99537226f",
    "name":"grep",
    "content":"Found 100 matches\n/home/.../foo.md:\n  Line 122, Char 1: ..."
  }
}
```

`content` may be very large (50KB+) for grep / bash / read on big files.
Consider truncation for index/search indexing (see hermes importer
reference: 50KB cap).

## 6. Role distribution (observed)

```
role        count (sample session, 184 messages)
---------   ------------------------------------
assistant    84
tool        133
user          4
```

There is **no `system` role**. System prompts / runtime messages are baked
into the assistant's first message as a `text` part (often the only part
when `text` is the system reminder). For importer purposes, the first
assistant message of a session is the closest analogue to a "system"
message.

## 7. Subagent encoding

Subagent (Task / Agent tool) invocations appear as tool_calls where
`name="agent"`. The `input.prompt` is the prompt passed to the subagent.
The subagent's own transcript is **not** nested in the parent session —
it's a separate session in the same DB (or a sibling DB if the subagent
ran in a different cwd). Look for:

```sql
SELECT * FROM sessions WHERE id LIKE '<parent_id>$$%' OR parent_session_id = '<parent_id>';
```

`messages.id` for subagent invocations uses the convention
`<parent_session_id>$$<tool_call_id>`, so `messages.id` is **not globally
unique** — it's a (session_id, tool_call_id) composite in practice. Don't
PRIMARY KEY on `messages.id` alone if migrating.

## 8. Field mapping cheat sheet (for hermes-style importer)

| crush column / json field              | target                                       | notes |
|----------------------------------------|----------------------------------------------|-------|
| `sessions.id`                          | `sessions.id` (TEXT)                         | keep as-is |
| `sessions.parent_session_id`           | `sessions.parent_id` (TEXT)                  | nullable |
| `sessions.title`                       | `sessions.title` (TEXT)                      | UNIQUE in hermes — handle collision |
| `sessions.message_count`               | `sessions.message_count` (INT)               | or recompute from COUNT(messages) |
| `sessions.created_at` (s)              | `sessions.created_at` (ms)                   | × 1000 |
| `sessions.updated_at` (s)              | `sessions.updated_at` (ms)                   | × 1000 |
| `sessions.prompt_tokens`               | `sessions.prompt_tokens` (INT)               | direct |
| `sessions.completion_tokens`           | `sessions.completion_tokens` (INT)           | direct |
| `sessions.cost`                        | `sessions.cost` (REAL)                       | direct |
| `messages.id`                          | `messages.id`                                | keep as-is, mind `$$tool_call_id` suffix |
| `messages.session_id`                  | `messages.session_id`                        | direct |
| `messages.role`                        | `messages.role`                              | direct |
| `messages.model`                       | `messages.model`                             | nullable |
| `messages.provider`                    | `messages.provider`                          | nullable |
| `messages.created_at` (s)              | `messages.created_at` (ms)                   | × 1000 |
| `messages.finished_at` (s)             | `messages.finished_at` (ms)                  | × 1000 |
| `messages.is_summary_message`          | `messages.is_summary_message`                | direct |
| parts text                             | `messages.content`                           | concat text parts, tool_calls as JSON list, tool_results as paired rows |
| parts tool_call                        | `messages.tool_calls`                        | JSON list of OpenAI-shape `{id,call_id,type,name,arguments}` |

## 9. Other tables worth knowing

- **`files`** — content-addressed cache of files the agent wrote or edited.
  Has its own `(path, session_id, version)` UNIQUE index. Importer can
  either copy it as a snapshot or skip — usually skip, it's redundant
  against the live filesystem.
- **`read_files`** — append-only log of which files the agent opened in the
  read tool. `(path, session_id)` PK. Useful for "what did crush actually
  inspect" forensics, not for the transcript itself.
- **`goose_db_version`** — goose migration tool's tracking table. Importer
  ignores.
- **`sqlite_sequence`** — autoincrement metadata, ignore.

## 10. Hot-backup before touching

Crush uses WAL by default (`.crush/crush.db-wal`, `.crush/crush.db-shm`).
A naive `cp crush.db backup.db` can miss uncommitted WAL pages. Use SQLite's
own backup primitive:

```bash
sqlite3 <db> ".backup <db>.pre-task-$(date +%s).bak"
```

Or in Python:

```python
src = sqlite3.connect(db_path)
dst = sqlite3.connect(backup_path)
with dst:
    src.backup(dst)
```

Always clean up backups after a successful import — use `trash`, not `rm`
(user preference).