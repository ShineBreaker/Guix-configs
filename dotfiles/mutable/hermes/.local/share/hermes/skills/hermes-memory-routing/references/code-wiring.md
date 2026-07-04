# Hermes Memory Code Wiring Reference

Exact file paths and line numbers that govern memory routing, verified against
the Hermes source tree at `/var/lib/distrobox-homes/my-distrobox/.local/share/hermes-agent/hermes-agent/`.

> Note: this user's Hermes is git-installed inside a distrobox home. Adjust paths
> if running from a different install (e.g. `$HERMES_HOME/hermes-agent/` in a
> stow/nix setup).

## Built-in MEMORY.md path

| Concern | File | Lines | Notes |
|---|---|---|---|
| Drift detection | `tools/memory_tool.py` | top of file | `_drift_error()` raises on round-trip mismatch; snapshots to `MEMORY.md.bak.<ts>` |
| Entry parser | `tools/memory_tool.py` | (search `_parse_entries`) | Splits on `§` delimiter; each entry becomes one line in the system prompt |
| System prompt snapshot | `tools/memory_tool.py::MemoryStore.load_from_disk` | ~133–164 | Frozen at session start to keep prefix cache stable |
| Nudge interval config | `config.yaml` → `memory.nudge_interval` (default 10), `memory.flush_min_turns` (default 6) | — | Per-turn push comes from `agent/prompt_builder.py` |
| Drift refusal message | `tools/memory_tool.py::_drift_error` | ~30 | Mentions `.bak.<ts>` snapshot and `remediation` field |

## Mirror hook wiring (built-in → external provider)

| Concern | File | Lines | Trigger |
|---|---|---|---|
| Tool dispatch for `memory` | `agent/agent_runtime_helpers.py` | 1747–1772 | Wraps `tools.memory_tool.memory_tool()` |
| Mirror call site #1 | `agent/agent_runtime_helpers.py` | 1759–1771 | Fires when `action in {"add","replace"}` and `agent._memory_manager` exists |
| Mirror call site #2 | `agent/tool_executor.py` | 1026 | Same condition, different dispatch path |
| Manager fan-out | `agent/memory_manager.py::MemoryManager.on_memory_write` | 611–639 | Iterates `_providers`, skips `name == "builtin"` |
| Holographic receiver | `plugins/memory/holographic/__init__.py::HolographicMemoryProvider.on_memory_write` | 244–251 | Calls `store.add_fact(content, category=...)` |

## Holographic plugin internals

| Concern | File | Lines | Notes |
|---|---|---|---|
| Schema (fact_store) | `plugins/memory/holographic/__init__.py::FACT_STORE_SCHEMA` | 38–74 | 9 actions: add/search/probe/related/reason/contradict/update/remove/list |
| Schema (fact_feedback) | `plugins/memory/holographic/__init__.py::FACT_FEEDBACK_SCHEMA` | 76–90 | Trains trust scores |
| Tool handlers | `plugins/memory/holographic/__init__.py` | 259–355 | `_handle_fact_store` and `_handle_fact_feedback` |
| System prompt block | `plugins/memory/holographic/__init__.py::HolographicMemoryProvider.system_prompt_block` | 183–204 | One-shot, no nudge |
| Prefetch | `plugins/memory/holographic/__init__.py::HolographicMemoryProvider.prefetch` | 206–220 | Returns top-5 facts above `min_trust`; called per-turn but the result is informational |
| Auto-extraction | `plugins/memory/holographic/__init__.py::_auto_extract_facts` | 359–397 | Weak English-pattern regex; doesn't fire without `auto_extract: true` |
| Store class | `plugins/memory/holographic/store.py` | — | SQLite with FTS5 triggers on `facts` table |
| Retriever | `plugins/memory/holographic/retrieval.py` | — | Implements search/probe/related/reason/contradict |

## Config keys (config.yaml)

```yaml
memory:
  flush_min_turns: 6                # turns between flush prompts
  memory_char_limit: 2000           # per-session system-prompt budget for MEMORY.md
  memory_enabled: true             # ← toggle this in Option B
  nudge_interval: 10                # ← the asymmetry root cause
  provider: holographic            # built-in | honcho | mem0 | holographic | retaindb | supermemory | openviking | byterover
  user_char_limit: 1375
  user_profile_enabled: true       # ← toggle this in Option B
  write_approval: false

plugins:
  hermes-memory-store:
    auto_extract: 'true'           # weak, see pitfalls
    db_path: ~/.local/share/hermes/memory_store.db
    default_trust: '0.5'
    hrr_dim: '1024'
    min_trust_threshold: 0.3       # filter floor for search/probe/reason
    hrr_weight: 0.3
    temporal_decay_half_life: 0    # 0 = no decay
```

## Quick probe script

```bash
HERMES_HOME="${HERMES_HOME:-$HOME/.local/share/hermes}"

echo "=== provider ==="
grep -E '^  provider:' "$HERMES_HOME/config.yaml"

echo "=== MEMORY.md size ==="
wc -lc "$HERMES_HOME/memories/MEMORY.md"

echo "=== facts count ==="
sqlite3 "$HERMES_HOME/memory_store.db" 'SELECT COUNT(*) FROM facts;' 2>/dev/null || echo "(no db)"

echo "=== facts by category ==="
sqlite3 "$HERMES_HOME/memory_store.db" \
  'SELECT category, COUNT(*) FROM facts GROUP BY category;' 2>/dev/null

echo "=== drift artifacts ==="
ls "$HERMES_HOME/memories/"*.bak.* "$HERMES_HOME/memories/"*.lock 2>/dev/null \
  || echo "(none — no drift)"
```

Diagnosis rule of thumb: MEMORY.md > 1 KB **AND** facts < 5 rows ⇒ routing is broken.

## System prompt context-files wiring (for "is X really injected?" questions)

When the user asks whether a particular file is actually loaded into the
system prompt — or when adding a SOUL.md rule that assumes something is loaded —
use this table to verify against the actual code path. SOUL.md prose can lie;
the loader functions cannot.

| Concern | File | Lines | Notes |
|---|---|---|---|
| Main context-file loader | `agent/prompt_builder.py::build_context_files_prompt` | 1514–1553 | Priority-first match, returns one block per session start |
| `.hermes.md` / `HERMES.md` loader | `agent/prompt_builder.py::_load_hermes_md` | (search) | Walks to git root |
| `AGENTS.md` / `agents.md` loader | `agent/prompt_builder.py::_load_agents_md` | (search) | Cwd only |
| `CLAUDE.md` / `claude.md` loader | `agent/prompt_builder.py::_load_claude_md` | (search) | Cwd only |
| `.cursorrules` / `.cursor/rules/*.mdc` loader | `agent/prompt_builder.py::_load_cursorrules` | (search) | Cwd only |
| SOUL.md loader (identity slot) | `agent/prompt_builder.py::load_soul_md` | (search) | Loads from `$HERMES_HOME/SOUL.md` |
| System prompt assembly | `agent/system_prompt.py` | 92, 296–304 | Calls `build_context_files_prompt` once per session start |

**Verified absent** (as of this user's install, hermes-agent distrobox path):

- `~/.agents/context/01-language.md`, `02-ultilities.md` — this is a pi-coding-agent / Crush convention. Hermes **does not** read this directory. Any SOUL.md claim referencing these files is documentation drift and should be edited out, not relied on.
- `~/.config/something/*.md` unless matched by the 4 rules above.

**Verification grep** (paste-adapt for the user's install path):

```bash
HERMES_SRC=/var/lib/distrobox-homes/my-distrobox/.local/share/hermes-agent/hermes-agent

# Find every context-loading function in the prompt builder:
grep -n "build_context_files_prompt\|_load_hermes_md\|_load_agents_md\|_load_claude_md\|_load_cursorrules\|load_soul_md" \
  "$HERMES_SRC/agent/prompt_builder.py"

# Verify a specific path is or isn't wired up:
grep -rn --include="*.py" "01-language\|02-ultilities\|/agents/context" \
  "$HERMES_SRC/agent/" "$HERMES_SRC/hermes_cli/" "$HERMES_SRC/tools/"
```

If grep #2 returns 0 hits, the path is not loaded by hermes. Either:

- **Edit SOUL.md** to remove the false claim (recommended — drift between docs and code is a bug).
- **Add a real loader** by extending `build_context_files_prompt` (requires patching hermes-agent source; for this user that means editing via their Nix flake in `~/Projects/Config/Guix-configs` per `guix-configs-workflow` skill).