---
name: single-source-doc-lint
description: "Lint repo docs for single-source-of-truth violations."
version: 0.1.0
author: Hermes
metadata:
  hermes:
    tags: [Docs, Lint, Single-Source-Of-Truth, Repo-Hygiene, Markdown]
    related_skills: [crush-session-extract, guix-configs-workflow, hermes-agent]
---

# Single-Source Doc Lint

Audit a repo's markdown / org documentation against four rules that came out
of a real Guix-configs cleanup session. Every doc on a doc tree drifts unless
there's a named authority for each piece of information — and the audit is
worth doing because tables that "should" be authoritative get out of sync
quietly, while stale directory names linger long after renames.

The four rules:

1. **Outdated docs/descriptions** — text that references paths, names, or
   configurations that no longer match the tree.
2. **Time-sensitive large tables** — tables whose contents change faster
   than the docs are reviewed.
3. **Tables whose data is regenerable** — if a single command or a single
   file already produces the table's contents, the table is duplicative and
   should be replaced by a pointer to that command/file.
4. **Single source of truth** — every piece of information has exactly one
   authoritative home; all other mentions should be references, not copies.

This skill codifies the audit workflow and ships one helper script. It does
**not** auto-edit your files; you read the candidates and decide.

The helper script `scripts/find_md_tables.py` is stdlib-only.

## When to Use

- "Audit this repo's docs for outdated references"
- "Find tables that duplicate regenerable data"
- "Find leftover `enable/` / `stow/` references after a rename"
- "Apply the single-source-of-truth rules from the Guix-configs cleanup"
- "Why is `AGENTS.md` out of sync with `.gitmodules` again"

Skip this skill when the user wants to fix the doc as they write it (use
the local repo's `AGENTS.md` routing rules instead) or when the doc set
is so small that a manual review is faster than running the scanner.

## Prerequisites

- Python 3.10+ (uses `pathlib.Path.rglob`).
- No MCP / no extra packages.
- The repo under audit is a working tree; no need to be clean (the script
  is read-only).

## How to Run

All work is done via the `terminal` tool. The helper lives at
`scripts/find_md_tables.py` and has two subcommands: `tables` and `paths`.
Read-only, no mutations.

## Quick Reference

```
# 1. find all "large" markdown tables (>= N body rows)
python3 scripts/find_md_tables.py tables --root <repo> --min-rows 5

# 2. find stale path references (default patterns target the
#    enable/ -> immutable/ and stow/ -> mutable/ renames)
python3 scripts/find_md_tables.py paths --root <repo>

# 3. JSON output for piping into a review buffer
python3 scripts/find_md_tables.py tables --root <repo> --json | jq

# 4. extend patterns for a different rename event
python3 scripts/find_md_tables.py paths --root <repo> \
    --patterns '\bold-name/' '\bdeprecated-namespace/'

# after editing, run a Guix Home deploy if dotfiles changed:
cd ~/Projects/Config/Guix-configs && blue home
```

## Procedure

The audit is five steps; do not skip the "regenerable" check (step 3) — it
is the one that catches the most entropy and saves the most future work.

### 1. Locate the docs surface

Run `tables` to enumerate every markdown table in the repo:

```
python3 scripts/find_md_tables.py tables --root <repo> --min-rows 5
```

Default `--min-rows 5` is the "definitely worth a second look" threshold.
Below that, the table is small enough that duplication is rarely a problem;
raise the threshold to 10+ if the repo is huge and you want to triage the
top offenders first.

Pipe to `--json` if you want to write the candidates into a review buffer
instead of a terminal scroll.

### 2. Locate stale path references

Run `paths` with the built-in rename patterns. The defaults target the
historical `enable/` → `immutable/` and `stow/` → `mutable/` rename in
Guix-configs. Override `--patterns` for a different rename event:

```
python3 scripts/find_md_tables.py paths --root <repo> \
    --patterns '\benable/agents\b' '\benable/desktop\b'
```

Hits in `.agents/workfile/` archive files are noise — they are historical
review notes that intentionally reference old paths. Filter those out of
your final todo.

### 3. Apply the four rules per candidate

For each table, ask the four questions in order. The order matters: rule
3 (regenerable) is the highest-leverage check, and rule 4 (single source)
only applies once you have decided to **keep** something.

| Question | If YES | If NO |
|----------|--------|-------|
| Q1 — Stale? | Edit or remove | Continue |
| Q2 — Time-sensitive content? | Note for periodic review | Continue |
| Q3 — Fully regenerable from one command or one file? | **Delete the table**, replace with a one-liner pointing to the command/file. This is the highest-value move. | Continue |
| Q4 — Does another doc already host the same data? | Delete this copy; point to the other doc | Keep, but mark its authority in a header note |

Worked examples from the source session:

- **`AGENTS.md` submodule table** (root): regenerable from
  `git submodule status` + `.gitmodules`. → Delete, replace with
  `"子模块列表见 .gitmodules（权威来源）"`.
- **`docs/secrets.md` subcommand table**: regenerable from
  `tools/secrets` (the script's `--help` / no-arg output). → Delete, replace
  with a pointer to the command.
- **`docs/loopctl.md` adapter table**: regenerable from
  `loopctl adapter list`. → Delete, replace with a pointer.
- **`AGENTS.md` global-variable table**: partial overlap with
  `source/information.scm`. The "类型" and "说明" columns are doc-only,
  but the "变量" column duplicates `information.scm`. → Keep, but add a
  header note: "变量名以 `source/information.scm` 为准".
- **`dotfiles/mutable/AGENTS.md` immutable-vs-mutable comparison**: this is
  the canonical explanation of the deployment model, **not** regenerable
  from any command. → Keep, no edit.

### 4. Edit with the right replacement pattern

When you delete a regenerable table, do not leave a hole. Replace it with
a one-liner pointer that names the command or the file:

```
| ... deleted table ... |
| --------------------- |
| ... deleted table ... |

子模块列表见 `.gitmodules`（权威来源），**不要直接编辑子模块内容**。
```

For path references, use the `patch` tool with `replace_all=true` when the
old name is fully consistent across the file (e.g. every `enable/agents/`
becomes `immutable/agents/`). Use `read_file` to scan the doc first; if the
old name is used in code blocks (a literal `bash` example), preserve those.

### 5. Deploy and verify

If the audited docs are deployed by Guix Home (`dotfiles/immutable/`):

```
cd ~/Projects/Config/Guix-configs
blue home                       # rebuild store, re-link to $HOME
ls -la ~/.config/<app>/         # confirm the link points at the new store hash
```

If the audited docs are in `dotfiles/mutable/` (stow flat-link), no deploy
step is needed — the link points directly at the repo source, edits are
live.

Then re-run both scanners. If they produce no new hits on the files you
edited, the cleanup is complete. If they produce hits only in
`.agents/workfile/` archive files, those are intentional and you are done.

## Pitfalls

- **Don't trust `messages.md` tables to be authoritative** for things like
  version numbers, package lists, or commit SHAs. They drift. Replace with
  the command that produces them.
- **`loopctl adapter list` exists, so the `loopctl.md` adapter table is
  duplicative** even though the doc is "nice to read". Don't keep both.
- **The repo's `home-dotfiles-service-type` `excluded` list excludes
  `AGENTS.md` and `README.md` from the deployed `~`.** Editing these files
  in the source does **not** require `blue home` to update the user's
  view; the docs only exist in the repo.
- **Filtering tables by row count alone misses inline 2-3 row tables**.
  Don't be too aggressive with `--min-rows` if the repo is small — start at
  3 and bump up if the list is too long.
- **A table that is "regenerable" but takes 30 seconds to regenerate is
  still worth deleting** if it is referenced often. Replacement value scales
  with reference frequency, not regeneration cost.
- **`disable/` is a graveyard** — directories moved there are intentionally
  not deployed. References to `dotfiles/disable/<x>` in active docs are
  almost always stale. The default patterns include `dotfiles/disable/`.
- **The scanner is line-based and misses tables split across unusual
  whitespace.** If you hand-authored a table with tabs, the row counter
  may under-count. Use `--json` to inspect raw output before trusting
  numbers.
- **Don't auto-replace `enable/` globally** without checking — it appears
  legitimately in `.agents/workfile/` archive notes that should stay
  verbatim for historical accuracy.
- **Rule 3 is the only one that shrinks the doc set long-term.** Rules 1, 2,
  and 4 only stop the bleeding. If you only have time for one rule per
  audit, do rule 3.

## Verification

A successful run produces all three:

1. `python3 scripts/find_md_tables.py tables --root <repo>` — fewer hits
   than before the audit, on the files you edited (other files' counts
   should not increase).
2. `python3 scripts/find_md_tables.py paths --root <repo>` — no hits in
   active docs (`.agents/workfile/` archive hits are noise).
3. A grep for any one of the deleted tables in `rg -l '<deleted header>'`
   — should produce no results in active docs.

If a hit reappears after a deploy, the Guix Home store still serves the
old copy — re-run `blue home` and check `ls -la ~/.config/<app>/` points
at the new store hash.

## Files

- `scripts/find_md_tables.py` — stdlib-only. Two subcommands:
  `tables` (find markdown tables with ≥N body rows) and `paths` (grep for
  stale path patterns, defaults target the Guix-configs renames).
- `references/judgment-examples.md` — annotated list of "delete vs keep"
  judgments from the source session, including the marginal cases
  (e.g. `global-variable table` with header note added).