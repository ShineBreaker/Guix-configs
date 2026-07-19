# Transcript density policy — for agent session extractors

> Cross-cutting reference for `*-session-extract` skills (codex, crush, future
> opencode / claude-code / pi extractors). When you write a new agent-session
> extractor, read this FIRST.

## Why this exists

In 2026-07-19 a codex session produced a 3.3 MB markdown that was
overwhelmingly noise — `token_count` rows, encrypted-reasoning placeholders,
full bash outputs that nobody would ever scroll through. The user's
explicit feedback was:

> "目前提取出来的东西由于 reasoning 加密的缘故，所有有用的文本非常少，
>  以及还有非常多的 `| 2026-07-19 11:08:25 CST | `` | token_count | {...}` 这种东西，
>  也是没必要提取出来的，我只需要有信息的对话数据"

Translation: **information density over completeness**. A 400 KB transcript
with every conversation beat preserved is more useful than a 3.3 MB
transcript where the signal is buried in operational telemetry and
encrypted stubs.

This file records the policy as a reusable class-level lesson. Apply it
to every new agent-session extractor you build.

## The policy in one sentence

**Keep user/assistant messages, tool calls, tool outputs, and
hand-off summaries. Drop operational telemetry, encrypted-only content,
boilerplate system prompts, and project-context injections that aren't
part of this session's dialogue.**

## Drop / keep matrix (apply to any agent's schema)

### Always drop

| Source pattern | Examples | Why |
| --- | --- | --- |
| Operational telemetry / events | `token_count`, `task_started` / `task_complete`, `turn_diff`, `turn_aborted`, `user_message` (duplicate of response_item user input), `thread_settings_applied`, `patch_apply_end` | Tracking data, not dialogue. |
| End-to-end encrypted content with no plaintext fallback | `reasoning` records with `encrypted_content: "gAAAAA…"` and no `text` / `summary`; `agent_message` blocks where every `content[]` part is `encrypted_content` | Cannot be recovered. Rendering a placeholder pollutes the doc with zero-info lines. |
| Boilerplate system prompts that apply to every session | `session_meta.base_instructions`, Claude Code's `system` array, Codex's "You are Codex, an agent based on GPT-5…" prompt | Same in every session — has no session-specific value. |
| Project-context injections that repeat every turn | `world_state` (codex), `claude.md` re-injection (claude-code) | Already in the model's context; not part of the dialogue. |
| Sub-agent control-plane records | codex's `inter_agent_communication_metadata`, claude-code's `control_request` | The actual signal shows up in tool output blocks. |

### Always keep

| Source pattern | Why |
| --- | --- |
| User / assistant message text | The dialogue. |
| Tool calls (name + args) | What the agent actually decided to do. |
| Tool outputs | What the agent learned. (Truncated per length policy below.) |
| Compaction / handoff summaries | Codex `compacted`, Claude Code "Context compacted" markers. They tell you what the prior half of the conversation was doing. |
| Top-level metadata for the session (header card) | Session id, start time, model, cwd, git. Useful for forensic reads. |
| Plaintext sub-agent messages | `FINAL_ANSWER` from a codex sub-agent contains real report text. Don't drop just because the block is `agent_message`. |

### Conditional: keep if non-empty, drop if boilerplate-only

- **Developer messages**: keep when they carry session-specific instructions
  (rare), drop when they're the same permissions/sandbox template repeated
  every turn.

## Length policy for tool outputs

The single biggest contributor to file bloat is tool outputs (grep /
find / cat / shell pipelines can return hundreds of KB). Apply this:

| Output length | Treatment |
| --- | --- |
| ≤ 800 chars | Full body inline as a fenced block |
| 801 – 4000 chars | First 800 chars inline; full body inside `<details><summary>Full output</summary>` collapsible |
| > 4000 chars | First 800 chars inline; body dropped, cite `(truncated, preview only)` with the original `call_id` so the reader can re-fetch from source |

These thresholds are tuned for the user's preference (density-first,
"happy to scroll past collapsed sections but not past endless pages of
shell output"). If the user later asks "I need the full output for
X", bump them — they're constants at the top of the extractor script.

## Reporting what was dropped

**Don't silently drop.** Add a `Dropped:` line to the document header
listing every category and count:

```markdown
- **Dropped**: encrypted reasoning × 232; event_msg × 284
  ({'task_started': 5, 'token_count': 190, ...});
  world_state / metadata
```

This does two things: (1) tells the reader the doc is incomplete (and
why), (2) gives a forensic breadcrumb if they later need to recover
something from the source.

## Implementation: where the rule lives

For each extractor, the rule lives in **two places**:

1. **One row per dropped category** in the SKILL.md "What is dropped"
   table — so the next agent reading the skill knows what's gone.
2. **The actual filter logic** in `scripts/<name>_extract.py` — the
   source of truth.

The reference here is the *cross-cutting rationale*. The per-extractor
skill documents the *specific* filter (e.g. "codex 0.144's
`custom_tool_call_output` agent_message filter"). The reference + the
per-extractor skill together should answer "what gets dropped and why"
without having to read the script.

## When to break the policy

The policy assumes the goal is **readable archival transcript**. Break
it when the goal is:

- **Machine re-import** into another store (e.g. hermes's `SessionDB`):
  preserve everything verbatim. → use `agent-session-import` instead.
- **Forensic / compliance audit** where every token matters: add a
  `--verbose` flag that bypasses the filters.
- **Debugging the extractor itself**: run with `--keep-all` and diff
  against the filtered output to verify the filter doesn't drop
  something that should be kept.

## Cross-references

- `../codex-session-extract/SKILL.md` §3 "What is dropped to keep the
  doc information-dense" — codex-specific instantiation of this policy.
- `../crush-session-extract/SKILL.md` — crush's existing truncation
  policy (4000 chars per tool_result, no per-category drop table) was
  written before this policy was articulated. If you revisit crush's
  extractor, align it with the conditional-keep / plaintext-sub-agent
  rules here.

## Provenance

Emerged from the 2026-07-19 session that re-implemented
`codex_extract.py` from a "preserve everything" v1 (3.3 MB output) to
a "density-first" v0.2.0 (434 KB output, 87% smaller, all conversation
beats preserved). The user's explicit framing:

> 我只需要有信息的对话数据

— "I only want the information-dense parts of the conversation data."

If you write a new extractor and ignore this policy, you will see the
same "this is mostly noise, can you redo it" message. Apply it by
default.