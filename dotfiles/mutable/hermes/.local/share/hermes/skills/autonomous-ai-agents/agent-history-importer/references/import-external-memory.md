# Importing External Agent Memory into Hermes

When migrating from another agent tool (zcode, pi, crush, Claude Code, Codex) into
Hermes, you need to import not just conversation history but the **project memory /
knowledge base** those agents accumulated. This reference covers the workflow for
importing markdown-based memory files into Hermes' three-channel memory system.

## The three Hermes memory channels

| Channel | Tool | When to use | Storage |
|---|---|---|---|
| `memory` (built-in) | `memory(action=add\|replace\|remove, target=memory\|user)` | Cross-project conventions, user preferences, global rules | `~/.local/share/hermes/memories/MEMORY.md` / `USER.md` |
| `fact_store` (holographic) | `fact_store(action=add\|search\|probe, category=project\|tool\|general)` | Project-specific facts, debug conclusions, deployment topology, command quirks | `memory_store.db` (SQLite FTS5) |
| `agenote` | `agenote add / search / list` | Cross-agent shared knowledge (gotchas, workarounds, design decisions) | `~/Documents/Org/agenote/` |

### Routing rule (user's hard rule)

**Question: "If I switch to a different project/repo, does this fact still matter?"**
- **Yes** → `memory` tool (markdown, always in prompt)
- **No** → `fact_store` (project-scoped, retrieved on demand)

## Workflow: import from external markdown memory

### Step 1: inventory the source

```bash
# Find all memory files (zcode layout: projects/<id>/memory/*.md)
find ~/.zcode/cli/memories -name '*.md' | head -50
# Count total
find ~/.zcode/cli/memories -name '*.md' | wc -l
```

Read every file. The content is usually structured as:
- Top-level index (`MEMORY.md`) listing sub-documents with one-line summaries
- Sub-documents with frontmatter (`name`, `description`, `metadata.type`, `metadata.node_type`)
- Each sub-document = one fact or one project's conventions

### Step 2: triage each document

For each file, decide its destination:

| Content pattern | Destination | Category |
|---|---|---|
| User preferences / workflow / style rules | `memory` tool | `target='user'` |
| Project conventions / decisions | `memory` tool | `target='memory'` |
| Bug root cause / deployment topology | `fact_store` | `category='project'` |
| Tool flag / config gotcha | `fact_store` | `category='tool'` |
| Cross-agent gotcha / workaround | `agenote` | `type=debug\|feature\|refactor` |

### Step 3: import to memory (built-in)

Use `memory(action=add, target=..., content=...)`. Watch out for:

- **Char limits**: `memory` tool has per-target limits (user: 2000 chars, memory: 4000 chars currently). If adding fails with "would exceed limit", consolidate overlapping entries or remove stale ones first.
- **Replace vs add**: if the content overlaps with existing entries, use `replace` with `old_text=<substring>` to merge rather than duplicate.

### Step 4: import to fact_store

Use `fact_store(action='add', content=..., entity=..., category=..., tags=...)`.

- `entity` = project name (e.g., `guix-configs`, `emacs-mobile`, `jeans`)
- One call per fact; batch with parallel tool calls
- Always `probe` first to avoid duplicates

### Step 5: import to agenote

Use `agenote add --title ... --category ... --type ... --owner ai --stdin <<EOF`.

**Pitfalls:**
- `type` field only accepts: `config`, `debug`, `feature`, `refactor`, `research`, `workflow`. `reference` is rejected with a warning but the file is still written — choose the closest valid type.
- `category` is free-form; reuse existing ones via `agenote fields --category` to maintain consistency.
- Content goes via stdin (`<<EOF` heredoc) to avoid shell-escaping issues with special characters.

### Step 6: verify

```bash
# memory: read back the file
cat ~/.local/share/hermes/memories/MEMORY.md

# fact_store: count by category
sqlite3 ~/.local/share/hermes/memory_store.db \
  'SELECT category, COUNT(*) FROM facts GROUP BY category;'

# agenote: list all cards
agenote list --all
```

## Learned lessons (2026-08 zcode → hermes migration)

1. **Memory tool space fills fast**: 64 zcode memory files → ~45 fact_store entries + 15 agenote cards + a few memory entries. The `memory` markdown file is only 86% full after importing just 4 entries because each prior session had already added content. Always check usage before batch-adding.

2. **fact_store `entity` aggregation matters**: grouping facts by `entity` (project name) makes `probe(entity=...)` retrieval return all related facts at once. Don't use a flat entity like "projects" — be specific.

3. **agenote frontmatter warnings are non-fatal**: `type 'reference' not in standard values` still writes the file. But future versions may reject it. Pick `debug` or `config` for reference-style knowledge.

4. **Don't import everything blindly**: some zcode memories are stale (e.g., "plan not yet committed" after the plan was committed). Verify against current state before importing.

5. **Parallel tool calls for batch**: fact_store and agenote calls are independent — batch them in a single response to avoid round-trip overhead.

6. **read_file with absolute paths**: `search_files` skips hidden directories (`.local`). Always use absolute paths when reading `~/.local/share/hermes/memories/*.md`.
