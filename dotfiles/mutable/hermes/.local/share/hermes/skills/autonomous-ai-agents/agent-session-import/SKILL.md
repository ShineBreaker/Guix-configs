---
name: agent-session-import
description: "Import conversation history from a third-party coding-agent CLI/TUI (pi, Claude Code, Codex, OpenCode, Aider, zcode, …) into Hermes's local session store so the conversations appear in `hermes sessions list` and can be resumed with `hermes --resume <id>`. Triggers: 'import pi/zcode sessions', '把 claude code / zcode 对话导入 hermes', 'migrate my chat history', '把 .codex/sessions 灌进 hermes', '恢复被删的 dotfiles'. Also handles recap work when hermes's `session_search` is empty but another agent left local state behind. **Before writing any importer against an agent's data dir, run `find ~ -name '*.db' -o -name '*.sqlite*' 2>/dev/null | grep -i <agent>` first — many agents (zcode, pi context-mode) keep the real session tree in a SQLite DB even when an obvious `*.jsonl` directory exists nearby.** For the related but narrower task of generating a schema reconnaissance report without writing the importer, see `agent-history-importer`."
version: 1.3.0
license: MIT
metadata:
  hermes:
    tags: [hermes, sessions, import, migration, pi, claude-code, codex, opencode, aider, zcode, state.db, sqlite]
    related_skills: [hermes-agent, hermes-skill-curation, agent-history-importer, skill-authoring]
---
# Agent Session Import

Bring conversation transcripts from a non-Hermes coding agent into the
local Hermes session store so they show up in `hermes sessions list`
and can be resumed with `hermes --resume <id>`.

## Core facts (Hermes side)

- Hermes session store is **SQLite** at `$HERMES_HOME/state.db`
  (`$HERMES_HOME` defaults to `~/.hermes/`, **but a Nix-installed
  `hermes-agent` package overrides it to `~/.local/share/hermes/`** —
  always check before writing).
- There is **no built-in session-level import CLI**. `hermes sessions
  {list,browse,export,delete,prune,rename,stats}` and the top-level
  `hermes import` (zip restore only) do **not** accept foreign JSONL.
- The correct write path is the in-process `SessionDB` API. Raw SQL
  works but reinvents schema/init/locks/FTS — don't.
- The Hermes Python venv ships at
  `/nix/store/<hash>-hermes-agent-env/bin/python3` on Nix installs
  and contains `hermes_state.SessionDB` plus `hermes_constants.get_hermes_home`.
  Your user-python may not import them; the importer script should
  re-exec itself under that python at runtime.
- On multi-store Nix hosts `ls /nix/store/*-hermes-agent-env/bin/python3`
  may return 4–5 paths — pick the one whose `hermes_state` import
  reports the user's `$HERMES_HOME` and re-resolve before writing.

## Write API cheat sheet (`hermes_state.SessionDB`)

| Method | Use |
|--------|-----|
| `create_session(session_id, source, **kw)` | New session row. `source` is the filter tag (e.g. `"imported-pi"`, `"imported-zcode"`). Optional: `model`, `model_config` (dict), `cwd`, `parent_session_id`. Does **not** accept `started_at` / `title` — back-fill via raw SQL on the same conn. |
| `append_message(session_id, role, content, ...)` | One message row. `role ∈ {"user","assistant","tool","system"}`. `content` scalar or list-of-parts (multimodal) — list/dict is auto-encoded as `"\x00json:" + json.dumps(...)`. For assistant: `reasoning_content` (str), `tool_calls` (OpenAI-style list), `finish_reason`. For tool: `tool_call_id`, `tool_name`. |
| `end_session(session_id, end_reason)` | Sets `ended_at = time.time()`. Override with raw `UPDATE sessions SET ended_at=?` afterwards if you want the real foreign timestamp. |
| `get_messages_as_conversation(session_id)` | Returns OpenAI-protocol message list — your single best round-trip verifier (see § Verify). |
| `get_session(session_id)` | Idempotency check: if not None, already imported. |

## Idempotency guard

`create_session` is `INSERT OR IGNORE` (via the `ON CONFLICT DO UPDATE`
in `_insert_session_row`) and silently no-ops on PK collision for the
session row itself, but `append_message` will still append duplicate
messages into the colliding session. Always check `get_session(foreign_id)`
first and bail out cleanly on conflict — otherwise a re-run doubles
the history.

## Conventions to enforce

- **Tag with a `source` string** (`"imported-pi"`, `"imported-zcode"`,
  `"imported-claude-code"`, etc.) so users can filter
  `hermes sessions list --source imported-zcode`.
- **Use the foreign session id verbatim** as Hermes session id (UUIDs
  are PK-safe and round-trip cleanly).
- **`end_reason`** = `"imported-<source>"` so the lineage is obvious
  in the UI / `sessions stats`.
- **`title`** = first 60 chars of the first user message, or the
  foreign session id as fallback.
- **`cwd`** = the foreign session's cwd (Hermes otherwise guesses from
  the importer process).
- **`message_count` / `tool_call_count`** are maintained by
  `append_message` automatically — do not pre-set them.

## Turn-coalescing trap

Most foreign agents occasionally split one logical assistant turn into
several adjacent message events (e.g. pi emits a `thinking`-only stub
then a separate message with the `toolCall` + text; zcode emits a
`step-start` then a separate message carrying the real `reasoning +
text + tool` parts). If you import those as separate Hermes rows, the
LLM on resume sees the wrong order: "assistant called tool, then
later thought about it". Importer must accumulate consecutive
assistant events into one merged row holding
`text + reasoning_content + tool_calls`. Verify: for any N
consecutive foreign assistant messages, you emit exactly 1 Hermes
assistant row.

## Content encoding pitfall

`assistant` rows with only `thinking + toolCalls` (no visible text)
must store `content = ""` (empty string), **not None**. The gateway's
`get_messages_as_conversation` passes through None as-is, and
OpenAI-protocol consumers interpret missing content as "the assistant
said nothing but never finished" — a guaranteed model error on resume.

## Time handling

- Foreign timestamps come in many shapes: ISO-8601 with trailing `Z`
  (pi, JSONL agents), **epoch milliseconds** (zcode SQLite `time_created`
  fields — `Date.now()` style), or seconds-since-epoch floats (hermes).
  *Always sniff before parsing.* `v / 1000.0 if v > 1e12 else float(v)`
  is the safe defensive coercion.
- ISO coercion: `datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()`.
- Maintain **strict monotonicity per session** (`max(prev+1ms, parsed)`)
  — Hermes orders messages by SQLite autoincrement id, but `timestamp`
  is still denormalized into many surfaces; out-of-order stamps break
  UI sorting and confuse session_search snippets.

## Verify (the four probes)

After importing, before telling the user it works:

1. **Row counts** — `SELECT role, COUNT(*) FROM messages WHERE session_id=? GROUP BY role;`
   matches the foreign message counts (modulo turn-coalescing).
2. **Tool-call pairing** — every `role='tool'` row has a non-null
   `tool_call_id`; that id appears in some `role='assistant'` row's
   `tool_calls` JSON.
3. **Round-trip** — `get_messages_as_conversation(session_id)` returns
   the same number of messages with `content` non-None on every
   user/assistant row.
4. **Live resume** — `timeout 30 hermes chat --resume <id> -q "续"` —
   if the agent loop actually fires (you see tool calls or a model
   response) instead of erroring on missing context, the import is
   end-to-end correct. Use a short timeout; you're verifying
   loadability, not getting the answer.

## Bash command gotchas

- `hermes sessions delete <id>` is **interactive** — pipe `yes` into
  it for scripted cleanup, or use the raw SQL
  `DELETE FROM messages WHERE session_id=?; DELETE FROM sessions WHERE id=?;`.
- `hermes -q "续"` is parsed as a subcommand. Correct one-shot resume:
  `hermes chat --resume <id> -q "续"`.
- Sandbox can flag heredoc pipelines `head … | python3 -c` as "Pipe to interpreter". Read first, write to a temp file, then `python3 tempfile` — or split the chain into a single `python3 << 'EOF'` heredoc (allowed when explicitly approved).

## Foreign agents often have MULTIPLE local data paths — check all

A recurring pitfall: agents that mimic the OpenCode architecture
(or ship a retroactive-indexing plugin) leave **3+ parallel stores**
that look unrelated. Always probe the directory tree before writing
import logic against the most obvious-looking file.

### Discovery command (run before anything else)

```bash
find ~/.local/share/<agent> ~/.cache/<agent> ~ -maxdepth 4 \
     -name '*.db' -o -name '*.sqlite*' -o -name '*.jsonl' 2>/dev/null \
  | grep -i <agent> | head -40
```

### Stores to know about

| Path                                            | Format | Contains                            | Use for          |
| ----------------------------------------------- | ------ | ----------------------------------- | ---------------- |
| `<agent>/sessions/*.jsonl` (pi)                 | JSONL  | Full conversation transcript        | direct import    |
| `<agent>/data/context-mode/sessions/*.db` (pi)  | SQLite | Structured metadata — no transcript | retrospective recap only |
| `<agent>/cli/db/db.sqlite` (zcode, OpenCode)    | SQLite | Full session+message+part tree, **JSON in TEXT columns** | direct import — **highest trust** |
| `<agent>/cli/rollout/*.jsonl` (zcode, OpenCode) | JSONL  | Per-API-call request/response mirror, **NOT a session log** | **ignore for import** |

The last row trips up many would-be importers: `rollout/*.jsonl` has
100+ lines per session and looks like a transcript, but on closer
inspection:

- `request.body.messages` is `[]` (only `system` content lives there)
- `response` is a flat `{text, toolCalls:[{id,name,input}], finishReason}`
  — no `role`, no content blocks, often no `thinking` persisted
- `request.messageCount` / `request.messageOffset` are your hint
  that the **true session content lives in a SQLite DB** elsewhere

**Rule:** when a foreign JSONL has the above shape, treat it as a
derived snapshot and hunt for the SQLite source-of-truth DB before
writing importer logic against the JSONL.

### pi "context-mode" DB (recap-only path)

pi (and likely other agents with retroactive indexing plugins) writes
**two parallel stores** that look unrelated:

| Path                                            | Format               | Contains                                       |
| ----------------------------------------------- | -------------------- | ---------------------------------------------- |
| `~/.local/share/pi/sessions/*.jsonl`            | JSONL (one event/line) | Full conversation transcript (original source) |
| `~/.local/share/pi/data/context-mode/sessions/*.db` | SQLite               | Structured metadata only — **no transcript text** |

Symptom of only checking the first path: `find ~/.local/share/pi -name
'*.jsonl'` returns nothing, you conclude "no pi history locally", but
the user actually has 6 months of history sitting in the DB. **Always
probe both paths before declaring foreign history missing.** The DB has
no `*.jsonl` extension, so a `*.jsonl`-only find will silently miss it.

#### When to query the context-mode DB (not the jsonl)

- The user's hermes `session_search` returns empty, but they say
  "I did X with pi before"
- `~/.local/share/pi/sessions/` doesn't exist (common after switching
  install methods — nix profile, compatible-mode `compat-dot-pi/`)
- The user asks "what have I been doing the last few months / audit my
  recent work / which files did we touch in project X"

Caveat: the context-mode DB **does not store transcript text** — it
only writes structured metadata events that the hook extracts from the
jsonl at runtime. If the jsonl is gone, you can't recover the actual
conversation, only a project-level activity map.

#### Path and discovery

```bash
# Main path (standard install)
~/.local/share/pi/data/context-mode/sessions/*.db

# Compatible-mode path (common on Nix/Guix home)
~/.local/share/pi/compat-dot-pi/context-mode/sessions/*.db
```

`find ~/.local/share/pi -name "*.db" -path "*session*"` catches both.

#### Schema (`session_events`)

```sql
CREATE TABLE session_events (
  id INTEGER PRIMARY KEY,
  session_id TEXT,
  type TEXT,                  -- intent / decision / file_write / file_edit /
                              -- file_read / git / external_ref / cwd /
                              -- tool_call / error_tool / error_resolved /
                              -- blocker_resolved / sandbox-execute / ...
  category TEXT,
  priority INTEGER,
  data TEXT,                  -- ← 关键: 内容在这里
  project_dir TEXT,
  attribution_source TEXT,
  attribution_confidence REAL,
  source_hook TEXT,
  created_at TEXT,
  data_hash TEXT
);
```

#### `data` field shape (by type)

| `type`           | `data` shape                                                                              | Use                                            |
| ---------------- | ----------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `intent`         | JSON `{"intent": "implement"}` / `{"intent": "investigate"}` — enum-style label          | Only tells you "implementing / investigating"  |
| `file_write`<br>`file_edit`<br>`file_read` | **bare path string**, e.g. `/home/u/Projects/X/foo.py` (no JSON wrapper)    | **core signal**: aggregate activity by path    |
| `git`            | JSON `{"raw": "commit"}` / `{"raw": "log"}` / `{"raw": "status"}` — command only        | counts only, **no commit message**             |
| `external_ref`   | JSON `{"url": "...", "prompt": "..."}` or bare URL                                          | which GitHub repos / docs got read             |
| `cwd`            | JSON `{"cwd": "/path"}`                                                                    | per-session working dir                        |
| `decision`       | extracted short text                                                                       | which forks the user picked                     |
| `error_tool`     | tool call error                                                                            | which tools keep failing                       |
| `blocker_resolved` | short text                                                                               | pairs with `error_*` to reconstruct stuck→resolved chains |

#### Retrospective SQL templates

```sql
-- 1) Top-level project activity (where the user spent time)
WITH paths AS (
  SELECT data AS p FROM session_events
   WHERE type IN ('file_write','file_edit','file_read')
     AND data LIKE '/home/%'
)
SELECT
  CASE
    WHEN p LIKE '/home/%/Projects/%' THEN
      'Projects/' || (regexp_extract(p, '^/home/[^/]+/Projects/([^/]+)', 1))
    WHEN p LIKE '/home/%/.config/%' THEN
      '~/.config/' || (regexp_extract(p, '^/home/[^/]+/\\.config/([^/]+)', 1))
    WHEN p LIKE '/home/%/Documents/%' THEN
      'Documents/' || (regexp_extract(p, '^/home/[^/]+/Documents/([^/]+)', 1))
    ELSE p
  END AS bucket,
  COUNT(*) AS hits
FROM paths
GROUP BY bucket
ORDER BY hits DESC
LIMIT 30;

-- 2) Per-repo activity (which specific repo is hottest)
SELECT
  regexp_extract(data, '^/home/[^/]+/Projects/([^/]+)/([^/]+)', 1)
    || '/' || regexp_extract(data, '^/home/[^/]+/Projects/([^/]+)/([^/]+)', 2) AS repo,
  COUNT(*) AS hits
FROM session_events
WHERE type IN ('file_write','file_edit','file_read')
  AND data LIKE '/home/%/Projects/%/%'
GROUP BY repo
ORDER BY hits DESC
LIMIT 30;

-- 3) Referenced GitHub / Codeberg repos
SELECT
  CASE
    WHEN data LIKE '%github.com%'  THEN regexp_extract(data, 'github\\.com/([^/"]+/[^/"]+)', 1)
    WHEN data LIKE '%codeberg.org%' THEN 'codeberg:' || regexp_extract(data, 'codeberg\\.org/([^/"]+/[^/"]+)', 1)
  END AS repo,
  COUNT(*) AS hits
FROM session_events
WHERE type = 'external_ref'
GROUP BY repo
ORDER BY hits DESC LIMIT 20;

-- 4) Weekly activity histogram
SELECT strftime('%Y-W%W', created_at) AS week, COUNT(DISTINCT session_id) AS sessions
FROM session_events
GROUP BY week ORDER BY week;
```

#### Retrospective golden trio (SQL + git)

The context-mode DB does not have commit messages — `git` events only
log the command name. To recover "what the user was actually doing"
you must **re-query the original repos**:

```bash
# Pull recent commits from top-3 repos identified by SQL
for repo in Projects/Config/Guix-configs Projects/Rust/Guix-conf-rs Projects/JS_TS/RecollectBeat; do
  cd ~/Projects/"$repo" 2>/dev/null || continue
  echo "=== $repo ==="
  git log --since="12 weeks ago" --author="$(git config user.email)" \
          --pretty=format:"%ad %s" --date=short | head -25
done
```

Crossing SQL aggregations with `git log` keywords (FEATURE / FIX /
REFACTOR / UPDATE / …) you can give a **theme-level** recap rather
than a project-level one: "restructured stow two-track + introduced
blue task runner + migrated channel to jeans".

#### Recap output structure (verified template)

Output is organized as **主线 + 副线** (main threads + side threads),
not by week:

1. **Main thread 1**: heaviest project + one-sentence framing + sub-themes
   (aggregate by FEATURE/FIX/REFACTOR/UPDATE keywords)
2. **Main thread 2**: next heaviest
3. **Side threads 1..N**: short, one-sentence each
4. **One-sentence summary**: tie all main threads together

Avoid weekly / daily listings (that's a log, not a recap). Avoid
per-session paragraphs (granularity too fine).

#### Relationship to the jsonl

- **jsonl present**: walk the standard `import-to-hermes.py` path;
  recap tasks filter `hermes sessions list --source imported-pi` and
  use `get_messages_as_conversation`.
- **jsonl gone (only context-mode DB remains)**: only SQL recap possible;
  explicitly tell the user "original transcripts lost, recap only".

### Spotlight: zcode (`~/.zcode/cli/db/db.sqlite`)

zcode is an OpenCode-architecture fork. The trap: it has **two**
parallel stores and the obvious-looking one (`rollout/*.jsonl`) is
**derived, not the source**. The SQLite DB is the source of truth.
Always run the discovery command in §"Stores to know about" first.

- `session` / `message` / `part` schema, per-part-type field shapes,
  end-to-end importer (idempotent, `--list` / `--dry-run` /
  `--all-parents`), and verify probes live in
  **`references/zcode.md`** — load it before writing any
  zcode-specific code.
- Subagent filter: `session.id NOT LIKE 'sess_subagent_agent_%'`
  gives parent sessions only. Subagent's first `user` message is the
  parent's task brief (Task tool prompt) — keep with `[subagent]`
  title prefix if you import it.
- Three zcode-specific gotchas bite every first-time writer:
  1. `rollout/*.jsonl` is per-API-call, **not** a session log.
  2. `time_created` is **milliseconds** (`Date.now()`), not seconds.
  3. `synthetic: true` user-text parts are auto-injected system
     reminders (TodoWrite nudges, skill hints) — fold to
     `[system-reminder] <first line>` so the LLM on resume doesn't
     mistake them for user intent.
- A working, end-to-end-verified importer lives at
  `scripts/import-zcode-to-hermes.py` in this skill. Reuse its
  shape (idempotency, source tag, four verify probes) when porting
  to other agents. Usage:
  ```bash
  scripts/import-zcode-to-hermes.py --list          # browse candidates
  scripts/import-zcode-to-hermes.py --dry-run <id>  # plan, no writes
  scripts/import-zcode-to-hermes.py <id>            # import one
  scripts/import-zcode-to-hermes.py --all-parents   # import all 31
  ```

## Working importers

The skill ships two runnable, idempotent importers under `scripts/`
(self-contained — backing up this skill directory is enough to keep
the tooling; see `skill-authoring` §1 for the principle):

- `scripts/import-pi-to-hermes.py` (1100+ lines). Reuse its shape
  (idempotency, turn-coalescing, source tag, four verify probes)
  when writing a new agent's importer; only
  `_split_<role>_content` + `_parse_ts` + the event-type switch
  need to change.
- `scripts/import-zcode-to-hermes.py` (end-to-end verified on a
  375-message session — 4 probes all pass). Auto-discovers the
  nix-store venv via `_resolve_hermes_py()`; override with
  `$HERMES_AGENT_PY` if hermes lives outside Nix. Modes: `--list`,
  `--dry-run`, single session, `--all-parents`.

If you need a schema reconnaissance report without writing the
importer (e.g. scoping work for a future session), see
`agent-history-importer` — it produces the per-agent field mapping
tables that go into the `references/<agent>.md` files this skill
consumes.

## Implementation pitfalls the reference skeleton above doesn't cover

These came up on the first working zcode importer — patch them in or
you'll hit them too:

1. **`end_session()` clobbers your backfilled timestamp.** `end_session`
   internally does `UPDATE sessions SET ended_at = time.time()` *only*
   when `ended_at IS NULL`. If you raw-SQL backfill `ended_at` and
   then call `end_session`, the second call no-ops. **But** if you
   call `end_session` first and then try to backfill, your backfill
   wins. The safe order is:
       1. `create_session(...)`
       2. raw SQL: `UPDATE sessions SET started_at=?, ended_at=?, title=?, end_reason=? WHERE id=?`
       3. (now optional) `end_session(...)` — only fires if ended_at is still NULL
   If you want to keep the importer simple, just skip step 3 and let
   the raw UPDATE in step 2 stand. Don't do both without checking —
   `end_reason` ends up double-prefixed (`"imported-imported-zcode"`).

2. **`get_session` is a write-side call.** It acquires the same
   `SessionDB._lock` and reads via `_conn`. In `--dry-run` mode you
   have **not** constructed a `SessionDB` (the nix-store python
   re-exec is skipped). The idempotency guard
   `if db.get_session(...):` must be
   `if db is not None and db.get_session(...):` — otherwise the
   dry-run path crashes with `AttributeError: 'NoneType' object has
   no attribute 'get_session'`.

3. **Synthetic user text is system chatter, not user intent.** zcode
   injects TodoWrite reminders and skill hints as `role='user'` rows
   whose text parts have `synthetic: true`. They pollute the
   conversation stream on resume (the LLM sees the system reminder as
   something the user "said"). Fold them to a one-line marker (e.g.
   `"[system-reminder] " + first_line[:120]`) instead of inlining
   the full text. Verified pitfall on sess_6a94a941 — leaving
   synthetic text in dropped live-resume quality visibly.

4. **Truncate long tool outputs.** A single `Bash` tool can return
   hundreds of KB of output (large `cat`, `find`, `grep -r`). Storing
   the full text in `messages.content` bloats `state.db` and slows
   FTS indexing. Cap at ~50 KB with a `[... truncated by importer ...]`
   suffix; the LLM on resume can re-run the tool if it needs more.

5. **Tool-call id namespace.** zcode uses `call_<hex>` (24+ hex chars)
   — not the Anthropic `toolu_xxx` shape and not the OpenAI
   `call_xxxxxxxx` shorter form. The id is on `part.data.callID`
   (note: not `part.data.id`, not `part.id`). Pair `tool` rows
   (hermes) to the parent assistant's `tool_calls[].id` on this
   field. Verify with the second probe (tool-call pairing).

6. **Backup before first import.** `cp ~/.local/share/hermes/state.db{,.pre-<agent>-import.bak}`
   is cheap and reversible. If the importer writes a row the gateway
   chokes on, recovery is one `cp` away.

## Out of scope

- `hermes import <zip>` is for restoring Hermes's own backups. Don't
  recommend it for foreign-agent migration.
- `hermes profile import` is for full-profile archives (config +
  skills + sessions). Use it only when the foreign "agent" is
  actually another Hermes profile.

## References

- `references/pi.md` — worked example: pi (`~/.local/share/pi/sessions/*.jsonl`).
  Covers ISO timestamps, `toolResult` vs OpenAI `tool`, split
  assistant turns, `bashExecution` non-standard role.
- `references/zcode.md` — zcode → hermes worked example
  (`~/.zcode/cli/db/db.sqlite`). Covers the "rollout/*.jsonl is
  derived, not the source" trap, millisecond `time_created`,
  OpenCode-style part tree, subagent filter, turn-coalescing
  across `step-start`/`step-finish` part borders.
- `skill-authoring` — why this skill is structured the way it
  is. The two structural principles (self-contained +
  progressive disclosure) are documented there, with this skill
  as the worked example.
