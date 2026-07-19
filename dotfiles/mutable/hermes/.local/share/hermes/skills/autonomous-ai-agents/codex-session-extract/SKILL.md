---
name: codex-session-extract
description: "Extract codex CLI sessions from JSONL rollout files into information-dense Markdown (or JSON) transcripts. Codex stores sessions at `~/.config/codex/sessions/YYYY/MM/DD/rollout-<ts>-<session-id>.jsonl` — one event per line, types are `session_meta` / `turn_context` / `event_msg` / `response_item` / `compacted` / `world_state`. The workhorse is `scripts/codex_extract.py` (stdlib only). The default policy **drops operational telemetry, encrypted reasoning stubs, boilerplate system prompts, and truncates tool outputs > 800 chars** — the user prefers a 400 KB readable transcript over a 3.3 MB raw dump. Use when the user says 'extract this codex session', '把 codex 这个会话抽成 markdown', '导出 codex 对话', 'codex session transcript', '这个 markdown 太多废话 / 过滤无用信息', '信息密度', or names a `019f…` session UUID. For the **narrower** task of importing codex into Hermes's local session store, see `agent-session-import`; for schema reconnaissance without writing the extractor, see `agent-history-importer`. For the **cross-cutting rationale** behind the drop/truncate policy (applies to all agent-session extractors), see `references/transcript-density-policy.md`."
version: 0.3.0
author: Hermes
metadata:
  hermes:
    tags: [Codex, Extract, Jsonl, Agent-History, Rollout]
    related_skills: [agent-session-import, agent-history-importer, crush-session-extract, skill-authoring]
---

# Codex Session Extract

Render Codex CLI session transcripts (per-session JSONL rollouts) into
Markdown or JSON for inspection, archival, or downstream processing.
Codex does **not** keep sessions in SQLite — every session is a
`rollout-<timestamp>-<session-id>.jsonl` line-stream under
`~/.config/codex/sessions/YYYY/MM/DD/`. This skill finds the right file,
streams it once, handles the multi-turn model-swap semantics, and emits a
clean transcript. It does **not** modify or delete the source file.

The workhorse script is `scripts/codex_extract.py` (stdlib only).

> **Before writing a new agent-session extractor or revisiting
> `crush-session-extract`'s defaults**, read
> `references/transcript-density-policy.md` — it documents the
> cross-cutting rationale (information density over completeness)
> that drives this skill's defaults. The defaults below are the
> codex-specific instantiation of that policy.

## When to Use

- "Extract this codex session as markdown"
- "把 codex 这个会话(给个 session id)抽成 markdown 文档"
- "Export a codex session I had yesterday / on 2026-07-18"
- "What did my codex agent do in session `019f74b5-…`?"
- "codex rollout jsonl 的 schema 是什么样的"
- "I want a transcript of my codex session, not the live CLI replay"

Skip this skill if the user wants to **import into Hermes's local
session DB** (use `agent-session-import`), or wants a live codex resume
(`codex --resume <id>` from the CLI). Use this when they want to
inspect or move sessions outside the live CLI, in human-readable form.

## Prerequisites

- Python 3.10+ (uses `pathlib.Path.rglob`, `Counter`, `defaultdict`).
- The `codex` CLI does **not** need to be running — extraction is
  read-only and works on a cold rollout file.
- No MCP / no extra packages / no `requests`.

## How to Run

All work is done via the `terminal` tool invoking `scripts/codex_extract.py`.
Two positional args: `<rollout.jsonl>` and `<output.md>` (or `.json`).

```bash
# Find a session file by id (or by date)
find ~/.config/codex/sessions -name '*019f74b5*'

# Extract
python3 scripts/codex_extract.py \
  ~/.config/codex/sessions/2026/07/18/rollout-2026-07-18T18-11-27-019f74b5-9d9f-72d1-a8b7-d227a6cf3b4c.jsonl \
  ~/Documents/Org/conversations/2026-07-18/codex-019f74b5-9d9f-72d1-a8b7-d227a6cf3b4c.md
```

## Quick Reference

```
~/.config/codex/sessions/                    ← root (configurable via --root)
  └── YYYY/MM/DD/                            ← date partition (UTC date in path)
       └── rollout-YYYY-MM-DDTHH-MM-SS-<session-id>.jsonl
```

Filename convention: `rollout-<timestamp>-<session-id>.jsonl`. The
timestamp is **session start** in UTC; the date partition uses the
**same UTC date** (not local time). A session that starts at 18:11
Asia/Shanghai on 2026-07-18 lives under `2026/07/18/`, not
`2026/07/19/`. Mind this when traversing by date.

## Procedure

### 1. Locate the rollout file

```bash
# by partial session id
find ~/.config/codex/sessions -name '*019f74b5*'

# by date range
find ~/.config/codex/sessions/2026/07/18 -name 'rollout-*.jsonl'

# all rollouts modified in the last 7 days
find ~/.config/codex/sessions -name 'rollout-*.jsonl' -mtime -7
```

The first match is the canonical file; the `session_id` field in
`session_meta.payload` is the authoritative id (the filename embeds the
same id, but trust the JSON if they ever disagree).

### 2. Verify it's the right session before extracting

A wrong-id extraction is silently lossy. Always confirm the session
before committing to a long render:

```bash
python3 -c "
import json
with open('<rollout.jsonl>') as f:
    for line in f:
        r = json.loads(line)
        if r.get('type') == 'session_meta':
            print('id:', r['payload']['session_id'])
            print('started:', r['payload']['timestamp'])
            print('cwd:', r['payload']['cwd'])
            print('cli:', r['payload']['cli_version'])
            break
"
```

### 3. Extract to Markdown

```bash
python3 scripts/codex_extract.py \
  <rollout.jsonl> \
  <output.md>
```

The script emits a single self-contained markdown file with these
sections, in order:

1. **Header** — session id, start time (local), CLI version, cwd, git
   branch/commit (if any), models used (with per-turn histogram),
   turn count, compaction count, source record histogram, and a
   dropped-counts line so the user sees what was filtered.
2. **Compaction summaries** — one subsection per `compacted` record
   (placed near the top because they're the most useful reconstruction
   aid for long sessions).
3. **Conversation turns** — one `### Turn N` subsection per
   `turn_context` record. Each subsection shows: timestamp, turn_id
   short, full model label (`model (effort=X, personality=Y)`), cwd.
   Inside the subsection, in arrival order:
   - 👤 User messages (verbatim text)
   - 🤖 Assistant messages (text + tool calls + tool outputs, all
     interleaved in arrival order)
   - 🛠️ Developer messages (sandbox / permissions / collaboration mode
     injected at turn start — only kept when they carry non-empty
     content)
   - ℹ️ System messages
   - Reasoning blocks at the top level (rare; usually nested in a
     message — see pitfalls below)

**What is dropped to keep the doc information-dense:**

| Source                          | Why dropped                                                                                  |
| ------------------------------- | -------------------------------------------------------------------------------------------- |
| `event_msg` (all subtypes)      | Operational telemetry: `task_started`, `task_complete`, `token_count`, `turn_aborted`, `turn_diff`, `user_message`, `agent_message`, `thread_settings_applied`, `patch_apply_end`, `context_compacted`, `sub_agent_activity`. Counts shown in header so the user sees it was filtered. |
| `world_state`                   | Injected `AGENTS.md` / project context. Same text every turn — pure noise.                  |
| `session_meta` JSON block       | All fields are already in the frontmatter header.                                            |
| `session_meta.base_instructions`| 16 KB+ of codex boilerplate system prompt — not dialogue.                                   |
| `inter_agent_communication_metadata` | Sub-agent signalling records; the actual signal is in `custom_tool_call_output`'s `agent_message` blocks. |
| `reasoning` records / parts with `encrypted_content` only | Reasoning is end-to-end encrypted; no plaintext can be recovered from a rollout. Rendered plaintext reasoning (rare) IS kept. |
| `custom_tool_call_output[].output[*]` blocks of type `agent_message` whose only content parts are `encrypted_content` | Same reasoning — drop pure-encrypted sub-agent messages but keep the plaintext ones (e.g. `FINAL_ANSWER` payloads from codex sub-agents) |

Per-tool rendering:

| Source                              | Rendered as                                                                                  |
| ----------------------------------- | -------------------------------------------------------------------------------------------- |
| `response_item.content[].type` = `text` / `input_text` / `output_text` | Inline paragraph                                                                |
| `response_item.content[].type` = `reasoning` (with plaintext) | `> **Reasoning**` blockquote                                                     |
| `response_item.content[].type` = `reasoning` (encrypted only) | **Dropped** (see table above)                                                  |
| `response_item.content[].type` = `function_call`             | `**🧰 Tool call — <name>**` followed by JSON args in a fenced block, with `call_id` (12-char prefix) for pairing |
| `response_item.content[].type` = `function_call_output`      | `**↳ Tool output**` followed by normalised output (see length policy below)     |
| `response_item.type` = `reasoning` (top-level)               | Same as nested reasoning: kept if plaintext, dropped if encrypted                |
| `response_item.type` = `custom_tool_call`                    | Codex 0.144+ format. The `input` field is a JS shim (`await tools.<name>({...}); text(r.output);`); the script extracts the JSON literal and renders it as clean JSON args, then renders as a normal tool call with `call_id` pairing. |
| `response_item.type` = `custom_tool_call_output`             | Same as `function_call_output`; output list is normalised (text blocks appended, pure-encrypted blocks dropped). |
| `response_item.content[].type` = `refusal`                   | `> **Refusal**: …` blockquote                                                          |
| anything else                       | HTML comment + raw JSON in a fenced block                                                  |

**Tool-output length policy** (this is what keeps the doc small):

| Output length        | Rendered as                                                                                  |
| -------------------- | -------------------------------------------------------------------------------------------- |
| ≤ 800 chars          | Full body inline as a fenced block (`text` or `json` based on first non-whitespace char)    |
| 801–4000 chars       | First 800 chars inline; full body in `<details><summary>Full output</summary>` collapsible  |
| > 4000 chars         | First 800 chars inline; full body dropped (cited as `(truncated, preview only)` with `call_id` so user can re-fetch from source jsonl) |

These thresholds are at the top of the script (`MAX_OUTPUT_INLINE = 800`). Adjust per use case if you need fuller transcripts (e.g. `MAX_OUTPUT_INLINE = 3000` to keep everything inline, at the cost of 3-4× larger output files).

### 4. Verify the output

Three sanity checks:

1. **Header turn count** matches `grep -c '"type": "turn_context"' source`.
2. **First user message** in the rendered file matches what the user
   remembers as their opening prompt.
3. **Tool calls / outputs are paired** — for every `**🧰 Tool call — …**`
   in the markdown, the next `**↳ Tool output**` with the same
   `call_id` prefix exists (or it's a call whose output is in the same
   turn's standalone list).

## Pitfalls (read these before running on a session you care about)

- **`agenote_extract` (MCP) is NOT a substitute.** It filters by date
  + source and will **miss** rollouts that span midnight in the host's
  timezone (the file lives under the UTC start date, not the local
  date). For "give me the markdown for session `019f74b5-…`", always
  go directly to `~/.config/codex/sessions/...jsonl`. Use
  `agenote_extract` only for "show me everything codex did on
  2026-07-19" (date-range queries where exact session id doesn't
  matter).

- **UTC date partition vs local date.** Codex partitions by the UTC
  start date of the session. A session started at 2026-07-18 22:11
  Asia/Shanghai (= 2026-07-18 14:11 UTC) lives under `2026/07/18/`,
  not `2026/07/19/`. `find` by date without time-zone awareness
  misses cross-midnight sessions.

- **Developer message comes BEFORE the first `turn_context`.** The
  very first response_item is a developer message injecting the
  sandbox/permissions/collaboration_mode block. If the script keys
  off `current_turn = None` for that record, it would silently drop
  the developer prompt. The script handles this by synthesising a
  pre-context `Turn 1` (model=`n/a`) when a message arrives before
  any `turn_context`. The TOC heading reads `### Turn 1 — … · `` · model=n/a`;
  that's expected, not a bug.

- **Model name lives in `turn_context.payload.model`, not in
  `session_meta.payload`.** The session_meta only has
  `model_provider` (e.g. `"fox"`) — the per-turn model label
  (`gpt-5.6-sol` / `gpt-5.6-luna` / etc.) is on each turn_context.
  If your markdown shows `model=n/a`, the synthetic-turn fallback
  fired (see previous pitfall) or the file is corrupted.

- **Model-swap mid-session.** Codex can switch model mid-conversation
  (e.g. `gpt-5.6-sol` → `gpt-5.6-luna`). Each switch is a new
  `turn_context` record and starts a new "Turn N" subsection. The
  script preserves this — a single session can have 4-8 turns even
  with only 2 user messages.

- **`function_call_output.output` can be str OR list of content
  blocks.** Older codex versions wrote a string; newer versions write
  `[{"type":"input_text","text":"…"}, …]`. The script normalises both,
  but if you write your own parser, handle both shapes.

- **`reasoning` is end-to-end encrypted.** The schema has
  `encrypted_content: "gAAAAA…"` and a separate (also-encrypted)
  `summary` array. You CANNOT recover the chain-of-thought from a
  rollout — it's encrypted client-side and only the model can decrypt
  it. Render the placeholder, don't try to base64-decode it.

- **`compacted` records are handoff summaries, not transcripts.**
  When Codex's context window overflows, it generates a summary and
  inserts a `compacted` record. The summary describes what the prior
  portion of the session was doing. Render these prominently — they
  are the single most useful reconstruction aid for long sessions.

- **Tool outputs are truncated above 800 chars by default.** A single
  bash tool on a large grep / find / cat can return hundreds of KB; the
  script keeps the first 800 chars inline, the next ~3 KB inside a
  collapsible `<details>`, and drops the rest with a `call_id` pointer
  to the source jsonl. If you need a fuller transcript, bump
  `MAX_OUTPUT_INLINE` at the top of the script. **Why this default
  exists:** the user explicitly asked for "only the information-dense
  parts of the conversation" — keeping the full output made a single
  8-turn session produce a 3.3 MB markdown that was mostly bash output.
  After tuning, the same session lands at ~370 KB with all conversation
  intact.
- **Encrypted reasoning is dropped, not rendered as a placeholder.**
  Earlier versions of the script rendered every `reasoning` part as
  `> **Reasoning** *(encrypted — original text not recoverable from
  rollout)*`. That preserved record structure but polluted the doc with
  232 zero-info blockquotes in an 8-turn session. The current version
  drops `reasoning` records/parts that contain only `encrypted_content`
  with no plaintext, and reports the count in the header's
  `reasoning_dropped` line so nothing is silently lost. If plaintext
  reasoning IS present (rare — only in some error/debug paths), it is
  rendered as `> **Reasoning**` blockquote.
- **`custom_tool_call` (codex 0.144+) wraps a JS shim, not JSON args.**
  The `input` field looks like
  `const r = await tools.exec_command({"cmd":"…","workdir":"…"}); text(r.output);`.
  The script extracts the JSON literal inside `tools.<name>(...)`,
  parses it, pretty-prints, and renders it as clean JSON args — so the
  markdown looks the same as for `function_call`. If parsing fails
  (e.g. the shim uses something other than a literal JSON object), the
  raw input is rendered as-is.
- **`custom_tool_call_output` contains sub-agent `agent_message`
  blocks.** Some sub-agent messages are pure `encrypted_content`
  payloads (dropped). Others carry plaintext bodies — e.g. a
  `FINAL_ANSWER` from a `/root/spec_review` sub-agent with a summary of
  spec deviations. These plaintext bodies ARE kept; the script's
  `normalize_output` filters per-block on the `encrypted_content` /
  `input_text` shape inside `agent_message.content[]`.

- **`session_meta.history_mode` / `context_window` are opaque
  metadata.** Render in the header JSON for forensic value but don't
  try to interpret them — Codex's session-windowing scheme changes
  across versions.

> The drop rules for `event_msg` / `world_state` / `base_instructions`
> / encrypted reasoning stubs all live in §3's "What is dropped"
> table above. The cross-cutting *why* lives in
> `references/transcript-density-policy.md`. Do not duplicate them
> here — the table is the source of truth.

## Verification

After running the full pipeline:

1. The output file exists and is non-empty (typically 200-500 KB for
   a long 8-turn session after the 2026-07-19 noise-filter pass;
   previously 1-5 MB before truncation kicked in).
2. The header `Turns: N` count equals `grep -c '"type": "turn_context"' source`.
3. The first `👤 **User**` block is the user's opening prompt.
4. The first `🤖 **Assistant**` block responds to that prompt (not to
   a later one — common error: extracting the wrong session file
   when multiple sessions share a date).
5. For any `**🧰 Tool call — <name>**` in the markdown, the
   corresponding `**↳ Tool output**` with the same `call_id` prefix
   appears in the same turn (or is missing — which is acceptable if
   the output was synthetic and rolled into the next turn).
6. The `Dropped:` line in the header accounts for every record type
   not present in the body. If `event_msg_dropped > 0` and `event_msg`
   isn't in the dropped list, something is silently rendering events.

## Files

- `scripts/codex_extract.py` — the only executable. Reads JSONL,
  emits Markdown. Stdlib only.
- `references/schema-cheatsheet.md` — full record-type reference,
  observed record-type distributions, example `response_item` shapes
  by `content[].type`, and the gotcha list above in condensed form.
- `references/transcript-density-policy.md` — the **cross-cutting
  rationale** for the noise-filter / drop / truncate defaults in this
  skill. Read it FIRST when writing a new agent-session extractor
  (or when revisiting `crush-session-extract`); the same policy
  applies there. Triggered by the user's recurring preference for
  information density over completeness (2026-07-19).

## Relationship to other skills

- **`agent-session-import`** — imports **into Hermes's local session DB**
  (`state.db`) so `hermes sessions list` shows them. Different goal
  (machine-readable, resumable) vs this skill (human-readable,
  archival).
- **`agent-history-importer`** — schema reconnaissance report
  (read-only, no extractor). Outputs the per-agent field mapping
  tables that importers/extractor authors consume. Use this skill
  when you've found a new codex version with breaking changes; use
  `codex-session-extract` when the schema is stable and you just
  want the markdown.
- **`crush-session-extract`** — same shape, different source.
  Crush stores in per-project SQLite; codex stores in per-session
  JSONL. The skill structure (`scripts/<name>_extract.py` +
  `references/schema-cheatsheet.md`) is intentionally parallel —
  when writing an extractor for a new agent, copy this skeleton.
  **Both skills should align with
  `references/transcript-density-policy.md`** (information-density
  preference, drop encrypted reasoning, truncate long tool outputs).
  Crush's current truncation limit (4000 chars, hard cutoff) was
  written before that policy and may want updating.
- **`skill-authoring`** §1 (self-contained principle) — this skill
  ships its own script and schema reference so a backup of the skill
  directory alone is enough to keep the tooling.