---
name: hermes-memory-routing
description: "Diagnose and fix the dual-channel memory problem in Hermes Agent — when `memory.provider: holographic` (or any external provider) is configured but the agent keeps writing only to `memories/MEMORY.md`, bypassing it. Covers why agents default to the markdown file, the four root causes of routing failure, and three remediation options (SOUL.md rules / disable MEMORY.md / mirror via code). Triggers on 'memory 不生效', 'holographic 没在用', 'agent 都写到 MEMORY.md', '双 memory 系统', 'memory tool vs fact_store', 'on_memory_write', 'memory drift', 'Mirrors 不到', or any 'why is my agent ignoring the configured memory provider' question."
version: 0.1.0
metadata:
  hermes:
    tags: [hermes, memory, holographic, fact-store, agent-routing, prompt-engineering]
    category: hermes-agent-ops
---

# Hermes Memory Routing

Hermes has **two independent memory channels** running side-by-side. When both are active and the agent keeps writing only to one, this skill explains why and how to fix it.

## The two channels

| Channel | Storage | Tool | System prompt presence |
|---|---|---|---|
| **Built-in MEMORY.md / USER.md** | `~/.local/share/hermes/memories/{MEMORY,USER}.md` (stow-tracked into git for this user) | `memory(action=add\|replace\|read\|remove)` | Strong — `memory_notifications: on` + `nudge_interval: 10` injects a "you haven't written memory in N turns" prompt every ~10 turns |
| **External provider** (holographic = SQLite FTS5 + trust + HRR; honcho/mem0/…) | `memory_store.db` for holographic; cloud for honcho | `fact_store` / `fact_feedback` (provider-defined) | Weak — single `system_prompt_block()` at startup, no per-turn nudge |

Both channels load their content into the system prompt at session start, but only the built-in channel actively **nudges** the agent to write during the session.

## Why the agent defaults to MEMORY.md (four root causes)

Diagnosing "agent ignores holographic" almost always lands on a combination of these:

1. **The nudge asymmetry** — `memory_notifications: on` + `nudge_interval: 10` fires every ~10 turns with text like "you have N turns since your last memory write". Holographic's `system_prompt_block()` only runs once at startup. The agent receives one strong periodic signal and one weak one-shot signal.
2. **write_file/patch is the path of least resistance** — `MEMORY.md` is just a markdown file the agent can read/edit with `read_file`/`patch`/`write_file`. For long narrative facts ("after three rounds of debugging, the only working fix is…"), writing to a file feels more natural than calling a tool with a single `content` argument.
3. **Drift detection punishes the markdown file** — `tools/memory_tool.py` has a `_drift_error()` guard that refuses to flush when MEMORY.md has been mutated outside the `memory` tool. If the user already has `MEMORY.md.bak.*` files + `.lock` files, drift has happened, which confirms write_file was used.
4. **The mirror hook only fires for the memory tool** — `MemoryManager.on_memory_write()` (in `agent/memory_manager.py`) is only called from `agent_runtime_helpers.py:1761` and `tool_executor.py:1026`, both wrapped around the `memory` tool dispatch. Any write via `write_file`/`patch`/`cat >>` **does not mirror** to holographic — the provider stays empty while MEMORY.md grows.

## Confirming the diagnosis

Quick probe — run all four; if any show asymmetry, the routing is broken:

```bash
# 1. What provider is configured?
grep -A2 'provider:' ~/.local/share/hermes/config.yaml | head -5

# 2. Where is the agent actually writing? (file size + git history)
ls -la ~/.local/share/hermes/memories/
wc -l ~/.local/share/hermes/memories/MEMORY.md

# 3. Where has holographic actually received facts?
sqlite3 ~/.local/share/hermes/memory_store.db \
  'SELECT category, substr(content,1,100) FROM facts;'

# 4. Is drift detection active (a sign write_file was used)?
ls ~/.local/share/hermes/memories/*.bak.* ~/.local/share/hermes/memories/*.lock
```

**Heuristic for "broken routing"**: MEMORY.md > 1 KB **AND** `facts` table < 5 rows.

## Three remediation options (pick by intent)

### Option A — Add a hard rule to SOUL.md (recommended when MEMORY.md is git-tracked canonical config)

The user wants both channels to work, with MEMORY.md remaining the readable / version-controlled truth. Add this block to `~/.local/share/hermes/SOUL.md` (which is the stow-tracked personalization file in `~/Projects/Config/Guix-configs/stow/hermes/.local/share/hermes/SOUL.md`):

```markdown
## Memory 双通道分工

你有两个独立的 memory 系统，不要混用：

| 系统 | 入口 | 适用内容 | 存储位置 |
|---|---|---|---|
| `memory` 工具 | `memory(action='add', content=..., target='memory'\|'user')` | 用户画像、偏好、跨会话决策；按 § 分条 | `memories/MEMORY.md` / `memories/USER.md` |
| `fact_store` 工具 | `fact_store(action='add', content=..., category=...)` | 项目事实、调试结论、命令诀窍、环境拓扑 | `memory_store.db`（holographic SQLite） |

### 默认分流

- 用户偏好 → `memory` 工具
- 排查出某 bug 的根因 / 部署拓扑 / 命令的坑 → `fact_store`，`category='project'`
- 工具/系统行为 / 配置项语义 → `category='tool'`

### 硬性约束

**禁止**用 `write_file` / `patch` / shell `cat >>` 直接编辑 MEMORY.md ——
会触发 `memory_tool.py::_drift_error`、丢数据，且 holographic 镜像收不到。
MEMORY.md 只能通过 `memory` 工具写入。
```

Pros: keeps MEMORY.md as git-tracked canonical, fixes routing, no code changes.
Cons: relies on the model respecting the rule — still possible to violate under pressure.

### Option B — Disable MEMORY.md, force everything through holographic

When the user wants a single source of truth and doesn't need markdown-readable memory:

```yaml
# config.yaml
memory:
  memory_enabled: false          # disable MEMORY.md
  user_profile_enabled: false    # disable USER.md
  provider: holographic         # keep only this
```

Plus a minimal SOUL.md rule:

```markdown
## Memory 写入（唯一通道）

你只有 `fact_store` 和 `fact_feedback` 两个记忆工具。没有 MEMORY.md，没有
"用 write_file 写记忆"这一说。

- 用户偏好 → `fact_store(action='add', content='...', category='user_pref')`
- 项目事实/调试结论/部署拓扑 → `category='project'`
```

Pros: eliminates the conflict entirely. No more drift, no more dual-source confusion.
Cons: existing MEMORY.md content must be migrated manually (`INSERT INTO facts SELECT ...`).

### Option C — Mirror MEMORY.md → holographic at session start (code-side)

For users who want MEMORY.md as truth AND holographic as the searchable layer. Two implementation paths:

1. **Quick-and-dirty**: a startup hook in `run_agent.py` that reads `memories/MEMORY.md`, parses `§`-delimited entries, and calls `store.add_fact(content, category=...)` for each. Idempotent thanks to `content TEXT NOT NULL UNIQUE` in the facts table.
2. **Mirror on every memory-tool write**: already works today via `MemoryManager.on_memory_write()`. The issue is that write_file bypasses this — fix at the agent level by adding a filesystem watcher on `MEMORY.md` that calls `_memory_manager.on_memory_write('add', 'memory', new_content)` on append.

Both require editing `~/.local/share/hermes/hermes-agent/` (the git-installed source). For this user's Guix-managed setup, the patch needs to go through their nix flake (`source/nix/flake.nix` → `programs/hermes.nix`) — see `guix-configs-workflow` skill.

## Background: how the mirror hook is wired

Code locations if you need to debug or patch:

| File | What it does |
|---|---|
| `tools/memory_tool.py::_drift_error` | Refuses to flush MEMORY.md when its content wouldn't round-trip through the parser. This is the `MEMORY.md.bak.*` source. |
| `agent/memory_manager.py::on_memory_write` (line ~611) | Manager that fans out writes to all external providers. |
| `agent/agent_runtime_helpers.py:1759-1771` | Calls `on_memory_write` after the `memory` tool dispatch (only path that fires). |
| `agent/tool_executor.py:1026` | Second caller of `on_memory_write` from the tool executor. |
| `plugins/memory/holographic/__init__.py::HolographicMemoryProvider.on_memory_write` | The receiver: mirrors `add` → `store.add_fact(content, category='user_pref' if target=='user' else 'general')`. |
| `plugins/memory/holographic/__init__.py::HolographicMemoryProvider.system_prompt_block` | One-shot system prompt text — has no per-turn nudge. |
| `agent/prompt_builder.py` (search `memory_notifications`) | Where the MEMORY.md nudge interval is enforced. |

## Tool mapping cheat sheet

| User wants to record… | Use this tool | Category |
|---|---|---|
| User likes X / I prefer Y / 我用 Z | `memory` | `target='user'` |
| Project uses / we decided | `memory` | `target='memory'` |
| Bug root cause confirmed after N rounds | `fact_store` | `category='project'` |
| Deployment topology / path quirks | `fact_store` | `category='project'` |
| Tool flag discovered / config gotcha | `fact_store` | `category='tool'` |
| Generic fact, no clear category | `fact_store` | `category='general'` |

## Pitfalls

- **Don't trust the `memory_char_limit` as a capacity signal** — it bounds how much of MEMORY.md gets injected into the system prompt per session, not total storage. The file can grow past it (compression handles overflow).
- **Trust scores decay silently** — holographic `min_trust_threshold` defaults to 0.3; facts below that won't appear in `search`/`probe`/`reason` results even though they're stored.
- **`auto_extract` is weak** — the regex patterns in `HolographicMemoryProvider._auto_extract_facts` only match English short sentences ("I prefer…", "we decided…"). Chinese long-paragraph facts (like the user's "经过三轮尝试，确认唯一有效修复为 X") won't be auto-extracted; they need explicit `fact_store(add)` calls.
- **`on_memory_write` only fires for `add`/`replace`** — not for `remove`, so if the user removes a MEMORY.md entry, holographic won't see it. Manually clean up holographic too.
- **Drift `.bak.*` files are real backups, not garbage** — if `_drift_error` triggered, the new content is in `MEMORY.md.bak.<timestamp>`; integrate those entries via `memory(add=...)` and remove the file, don't just delete it.
- **SOUL.md documentation can lie about what's injected** — A SOUL.md may say "global context: `~/.agents/context/01-language.md`", but that file is *not* injected unless the actual code path loads it. Always grep the codebase to confirm before claiming "X is in your system prompt." (See "Verify before claiming" below.)

## Verify before claiming "this is in your context"

When the user asks "is X actually loaded into the system prompt?" — or when you want to claim something is loaded — do **not** rely on what you "know" about the agent's configuration or on SOUL.md's documentation. Grep the code.

```bash
# What gets injected as project context (4 source types only, in priority order):
grep -n "build_context_files_prompt\|_load_hermes_md\|_load_agents_md\|_load_claude_md\|_load_cursorrules" \
  /var/lib/distrobox-homes/my-distrobox/.local/share/hermes-agent/hermes-agent/agent/prompt_builder.py
```

The full inventory at session start is built by `build_context_files_prompt()` in `agent/prompt_builder.py` (~line 1514). It loads, in this priority order:

1. `.hermes.md` / `HERMES.md` (walked to git root)
2. `AGENTS.md` / `agents.md` (cwd only)
3. `CLAUDE.md` / `claude.md` (cwd only)
4. `.cursorrules` / `.cursor/rules/*.mdc` (cwd only)
5. + `SOUL.md` from `$HERMES_HOME` (only when `skip_soul` is false)

**Anything not in this list is NOT loaded automatically** — including:

- `~/.agents/context/*.md` (this is a pi-coding-agent convention; hermes does not honor it)
- `~/.config/something/*.md` (unless matched by the 4 rules above)
- Any "shared cross-agent context" file the user mentions in SOUL.md (treat the SOUL.md claim as suspicious until grep'd)

**Verification recipe** when the user asks "is X really injected?":

```bash
# 1. Where does the user's config claim X lives?
grep -n "X\|01-language\|02-ultilities\|global.context" ~/.local/share/hermes/SOUL.md

# 2. Does any code path actually read that path?
grep -rn --include="*.py" "01-language\|02-ultilities\|/agents/context" \
  /var/lib/distrobox-homes/my-distrobox/.local/share/hermes-agent/hermes-agent/

# 3. If grep #2 returns 0 hits, the file is a ghost — not injected, no matter what SOUL.md says.
```

Then either:

- **Update SOUL.md** to remove the false claim (recommended — drift between docs and code is a bug).
- **Add a real loader** if the user wants that file injected (requires extending `build_context_files_prompt`, which means editing the hermes-agent source — go through the user's Nix/Guix pipeline for this user's setup, see `guix-configs-workflow`).

This applies to *any* "is X loaded?" question in this user's setup, not just memory. The class of error is: **trusting SOUL.md's English description over what the code actually does.**

## Related skills

- `hermes-agent` — the bundled meta-skill for Hermes configuration (do not edit, but contains the canonical config schema and CLI references).
- `guix-configs-workflow` — for deploying Hermes config changes through the user's Guix + Nix flake + stow pipeline (SOUL.md lives under `stow/hermes/...` in their setup).
- `importing-agent-prompts` — when porting memory-related prompt conventions from other agents (pi, Claude Code, Codex).
- `hermes-skill-curation` — for the meta-question of how this skill itself should be maintained.

## Files in this skill

- `references/code-wiring.md` — exact file paths and line numbers in the Hermes source tree for `memory_tool.py`, `MemoryManager.on_memory_write`, holographic internals, and config keys. Use when debugging or patching.
- `templates/soul-memory-rule.md` — drop-in SOUL.md block implementing Option A (dual-channel routing rule). Copy into `~/.local/share/hermes/SOUL.md` and edit the category list to match your projects.
- `scripts/probe-memory-routing.sh` — runs the diagnosis heuristic from this skill in one shot. Exit code 2 means routing is broken. Run as `bash scripts/probe-memory-routing.sh` (or `chmod +x` once and invoke directly).