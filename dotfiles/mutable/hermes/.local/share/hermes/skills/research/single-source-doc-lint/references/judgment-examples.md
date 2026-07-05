# Judgment examples — single-source-doc-lint

Annotated "delete vs keep" decisions from the source audit. Use this as a
calibration set when applying the four rules to your own repo.

## Hard deletes — rule 3 (regenerable) wins

These tables were deleted in the source session because a single command or
file already produces their contents.

### `AGENTS.md` (root) — submodule table (6 rows)

| 路径 | 上游 |
|------|------|
| `dotfiles/mutable/emacs/.config/emacs/general-config` | `codeberg.org/BrokenShine/.emacs.d` |
| ... | ... |

**Why delete:** `.gitmodules` is the authoritative source for both columns.
`git submodule status` lists the actual paths and SHAs. The table duplicates
both, and the two will diverge within one submodule bump.

**Replacement:**

```
子模块列表见 `.gitmodules`（权威来源），**不要直接编辑子模块内容**。
```

### `docs/secrets.md` — subcommand table (9 rows)

**Why delete:** `tools/secrets` (no args) prints the same list. The doc
table goes stale whenever a subcommand is added or renamed.

**Replacement:** "运行 `tools/secrets` 查看所有子命令".

### `docs/loopctl.md` — adapter table (6 rows)

**Why delete:** `loopctl adapter list` prints the same data from the
adapter JSON files.

**Replacement:** "Adapter 列表运行 `loopctl adapter list` 查看".

### `dotfiles/mutable/AGENTS.md` — secrets subcommand table (lines 110-114)

**Why delete:** Same as the secrets.md table. The doc and the script were
both in the same repo and the doc version was older.

**Replacement:** "运行 `tools/secrets` 查看所有子命令".

## Hard keeps — not regenerable, no duplication

### `dotfiles/mutable/AGENTS.md` — immutable-vs-mutable comparison table

**Why keep:** This table is the canonical explanation of the deployment
model itself. There is no command or file that produces it; it is original
content. The two columns name concepts, not data.

### `dotfiles/immutable/agents/AGENTS.md` — startup script table

**Why keep:** Small utility table (4-5 rows). Duplicating the contents
across the doc and the actual scripts directory would only matter if the
scripts moved; the cost of the duplication is below the cost of replacing
the table with a generated pointer.

## Marginal — keep with an authority note

### `AGENTS.md` (root) — global-variable table (6 rows)

```
| 变量 | 类型 | 说明 |
| ... | ... | ... |
```

**The marginal case:** The "变量" column duplicates `source/information.scm`.
The "类型" and "说明" columns are doc-only and not derivable from any file.

**Decision:** Keep, but add a header note:

```
> 变量名以 `source/information.scm` 为准；类型 / 说明列是 doc-only 注释。
```

This honours rule 4 (single source) without forcing readers to jump to
`information.scm` for what is genuinely commentary.

### `AGENTS.md` (root) — channel architecture table (5 rows)

**The marginal case:** URL and branch columns come from `source/channel.scm`.
The "职责" column is original commentary.

**Decision:** Keep, trimmed to just the "职责" column with a header note
pointing to `source/channel.scm` for URL/branch.

## Hard deletes — rule 1 (stale) wins

### `dotfiles/AGENTS.md` line 152 — `enable/agents/` reference

```
### oh-my-pi + Crush + loopctl（`enable/agents/`）
```

**Why:** The directories were renamed from `enable/` to `immutable/` and
`mutable/` months before the audit. The doc was missed.

**Fix:** Replace `enable/agents/` with `immutable/agents/` (and similar
for `desktop/`, `noctalia-suite/`, `system/`, `terminal/`, `utilities/`).
Same fix in `dotfiles/AGENTS.md` and `dotfiles/immutable/agents/AGENTS.md`.

## Rule 3 is the only one that shrinks the doc set

Rules 1 (stale) and 2 (time-sensitive) only stop the bleeding; rule 4
(single source) only stops duplication. Rule 3 (regenerable) actually
removes content from the doc surface, which is what gives the audit a
lasting effect.

If you only have time for one rule per audit, do rule 3. Even on a small
repo, deleting one or two regenerable tables and replacing them with
pointers usually pays for itself within a few months.

## Source

These judgments were captured during the 2026-07-05 Guix-configs cleanup
session (`AGENTS.md` → 5 changes, `docs/secrets.md` → 1, `docs/loopctl.md`
→ 1, `dotfiles/AGENTS.md` → 1, `dotfiles/mutable/AGENTS.md` → 2,
`source/AGENTS.md` → 1, plus 9 stale `enable/` → `immutable/` renames
across `dotfiles/AGENTS.md` and the hermes agent skill files). Use
`crush-session-extract` to read the full transcript.