---
name: crush-session-extract
description: "Extract crush CLI sessions from per-project SQLite DBs."
version: 0.1.0
author: Hermes
metadata:
  hermes:
    tags: [Crush, Extract, Sqlite, Agent-History, Per-Project]
    related_skills: [agent-history-importer, importing-agent-prompts, hermes-agent]
---

# Crush Session Extract

Pull sessions out of the `crush` CLI's per-project SQLite store and render them
as Markdown or JSON transcripts. The store is **not** a flat file like most
agent tools — every project keeps its own `<project>/.crush/crush.db`, and the
schema comment about millisecond timestamps is a lie (it stores seconds).
This skill finds the right DB, validates the time unit, hot-backups the file,
and emits a clean transcript. It does **not** modify or delete sessions.

The workhorse script is `scripts/crush_extract.py` (stdlib only).

## When to Use

- "Extract today's conversations with crush"
- "Pull the crush session for project X into a Markdown transcript"
- "Where does crush save its DB?"
- "crush's schema says `created_at` is milliseconds but my dates are 1970"
- "Migrate crush sessions to hermes / org / my own archive"

Skip this skill if the user wants a one-shot peek — `crush run` resume is
already on the CLI (`crush --session {id}`). Use this when they want to
inspect or move sessions outside the live CLI.

## Prerequisites

- Python 3.10+ (uses `sqlite3.Connection.backup`, `pathlib.Path.rglob`).
- The `crush` CLI itself does **not** need to be running — extraction is
  read-only and works on a cold DB.
- No MCP / no extra packages.

## How to Run

All work is done via the `terminal` tool invoking `scripts/crush_extract.py`.
The script has five subcommands: `find`, `list`, `show`, `dump`, `verify`.

## Quick Reference

```
# locate every per-project crush DB
python3 scripts/crush_extract.py find --root ~

# hot-backup + cross-check message_count column vs actual row count
python3 scripts/crush_extract.py verify --db <project>/.crush/crush.db

# list sessions in a date window (auto-detects seconds vs ms)
python3 scripts/crush_extract.py list --db <db> --since YYYY-MM-DD --until YYYY-MM-DD

# show metadata + actual vs column message count for one session
python3 scripts/crush_extract.py show --db <db> --session <id>

# render one session as Markdown transcript (or --format json)
python3 scripts/crush_extract.py dump --db <db> --session <id> --format md --out transcript.md
```

## Procedure

### 1. Locate the DB (per-project, not global)

Crush does **not** store sessions in `~/.crush/`. It writes
`<project>/.crush/crush.db` *per project*, alongside `.gitignore`. The global
file at `~/.config/crush/.crush/crush.db` is only a `goose_db_version`
migration header and has no session rows.

```
python3 scripts/crush_extract.py find --root ~
```

Output is one row per DB: size, mtime, session count, message count,
absolute path. The script skips `Trash/` and `.bak` files automatically.

If the user's target project isn't in the output, walk a wider root
(`--root /home/<user>`), or pass the path explicitly to `--db`.

### 2. Verify before extracting

Always run `verify` first on the source DB. It does two things in one shot:

- **Hot backup** via SQLite's `Connection.backup()` (WAL-safe). Output is
  `<db>.pre-verify-<ts>.bak` next to the source. Use `trash <bak>` to remove
  after a successful import — never `rm`.
- **Cross-check** the `sessions.message_count` column against the actual
  `COUNT(*) FROM messages WHERE session_id = s.id` per session. If any
  mismatch, the script exits 1 and lists the offenders.

```
python3 scripts/crush_extract.py verify --db <project>/.crush/crush.db
```

If the schema looks broken (count drift, orphan rows), stop and read
`references/schema-cheatsheet.md` before proceeding.

### 3. Pick the session(s)

List with a date window. The script detects the time unit (see step 4) and
prints ISO timestamps; no math required on the agent's side.

```
python3 scripts/crush_extract.py list \
  --db <project>/.crush/crush.db \
  --since 2026-07-05 --until 2026-07-05
```

Copy the full UUID from the output (the column shows only a 16-char prefix;
the script needs the full id for `dump`/`show`).

### 4. Time unit is SECONDS, not milliseconds

This is the single biggest pitfall. The schema says:

```
created_at INTEGER NOT NULL,  -- Unix timestamp in milliseconds
```

The comment is wrong. `created_at` for sessions created today is
`~1783258809` (seconds since epoch), not `~1783258809000`. Naively doing
`datetime(value, 'unixepoch')` works; doing `datetime(value/1000,
'unixepoch')` lands you in 1970.

`verify` auto-detects this and prints `# unit detected: seconds`. The
heuristic: if `MIN(created_at)` falls in `[2024-01-01 UTC, now+1d]`, treat
as seconds; if the same range in ms, treat as milliseconds. The script
applies the same conversion everywhere internally — but if you hand-write
SQL, **don't divide by 1000**.

### 5. Dump to Markdown or JSON

```
python3 scripts/crush_extract.py dump \
  --db <project>/.crush/crush.db \
  --session <full-uuid> \
  --format md \
  --out transcript.md
```

The Markdown rendering:

- Per-message `## [N] <role>  (<ISO timestamp>)` header.
- `text` parts inline as paragraphs.
- `reasoning` parts wrapped in `> **reasoning:**` blockquotes (preserves
  Crush's chain-of-thought separately from user-visible text).
- `tool_call` parts render `**→ tool_call <name>` followed by the JSON input
  in a fenced block. `tool_result` renders the content in a fenced block,
  truncated to 4000 chars with a marker (Crush tool outputs are frequently
  huge).
- `finish` parts render as a one-liner with reason + time.
- Unknown `part.type` values are dumped inline as an HTML comment so the
  Markdown still validates.

JSON mode dumps the raw rows + parsed `parts` arrays with no rendering —
use it for re-importing into another store.

### 6. Optional: re-import into hermes / Org / your archive

For hermes specifically, the existing `agent-history-importer` skill's
Section 12 (`zcode-schema.md`) is the cheat sheet for writing hermes
`SessionDB` rows. Use `crush_extract.py dump --format json` as the input
source — `messages.parts` is already a parsed list, not a JSON string.

For Org / Markdown archive, `--format md` is the canonical form; pipe it
into `~/Documents/Org/conversations/crush-<date>-<id>.org` using
`terminal` (hermes desktop file browser picks it up automatically).

## Pitfalls

- **Global `~/.config/crush/.crush/crush.db` is empty.** It only holds the
  `goose_db_version` migration row. All sessions are in `<project>/.crush/`.
- **Time unit is seconds, not ms.** Schema comment is wrong. Verify warns
  on first run if it can't auto-detect.
- **`messages.id` is not globally unique.** Subagent tool invocations reuse
  the parent session id with a `$$<tool_call_id>` suffix, so
  `SELECT DISTINCT id` lies. Use `id, session_id` as a composite key.
- **`parts` is a JSON TEXT array.** Use `json_each(messages.parts)` to
  filter by type. `json_extract(parts, '$[0].type')` only sees the first
  element — Crush often emits `[reasoning, text, tool_call, ...]`.
- **`read_files` table is per-session, not per-message.** It tracks which
  files the agent opened in the editor; useful for "what did crush touch"
  forensics but not part of the transcript.
- **`files` table is a content-addressed cache**, not user uploads. Don't
  confuse with attachments.
- **`session.message_count` is maintained by a trigger**, but the trigger
  only fires on INSERT/DELETE — a manual UPDATE to messages bypasses it.
  `verify` catches drift.
- **Crush session ids can collide on the prefix.** The `list` output shows
  only 16 chars; copy the full id from `show --session` if unsure.
- **Tool outputs can be enormous** (grep over the whole repo, etc.). The
  Markdown renderer truncates to 4000 chars per tool_result; JSON mode
  preserves the full content for archival use.
- **Subagent transcripts live in a different DB.** Crush spawns subagents
  in a sibling project (`.crush/...`) — they're not nested in the parent
  `messages.parts`. To follow a subagent, run `find --root <project>` and
  look for a sibling DB.

## Verification

After running the full pipeline, the script should pass these three checks:

1. `verify` exits 0 and prints `# message_count column matches actual count for all sessions ✓`.
2. `list --since <today> --until <today>` shows every session the user
   remembers having today.
3. `dump --format md --out /tmp/x.md` produces a non-empty file whose first
   `## [1] user` heading matches the user's opening prompt.

If any of these fail, the time unit is probably wrong, or the DB path points
at the global empty one. Re-run `find --root ~` to confirm.

## Files

- `scripts/crush_extract.py` — the only executable. Five subcommands, stdlib only.
- `references/schema-cheatsheet.md` — full DDL + every observed `part.type` sample JSON + field mapping table for importer authors.