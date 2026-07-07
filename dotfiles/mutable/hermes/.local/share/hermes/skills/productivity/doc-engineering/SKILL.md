---
name: doc-engineering
description: "When the user says '校对文档 / 检查文档是否还有效 / sync doc with code / 扩写 README / 改写文档 / 把这个 PLAN/plan/任务书做成文档 / 文档并入主文档', or when a `refs/*.md` document may be drifting from the tool/CLI/源码 it describes, or when a PLAN file needs to become a user-facing reference doc. Covers three entry points — check, rewrite, plan-to-doc — backed by a `scripts/doc-check.py` checker that catches silent drift between a doc and its source-of-truth (CLI flags, MCP tool names, file paths). Trigger when the user names a doc path and asks whether it's still accurate, when adding a new CLI/MCP/API surface that old docs don't mention, or when a PLAN/任务书/thread needs to graduate into a stable reference."
version: 0.2.0
license: MIT
metadata:
  hermes:
    tags: [doc-review, doc-rewrite, plan-to-doc, drift-check, CLI-sync]
    related_skills: [skill-authoring, single-source-doc-lint, unknown-discovery]
---

# Document Engineering

Three entry points, one checker, never trust a doc to stay
accurate without re-running it.

## 1. Three entry points — pick one, then go to §3

| Goal                                                          | Entry point     | See                             |
| ------------------------------------------------------------- | --------------- | ------------------------------- |
| "Is this doc still accurate? What drifted?"                   | **check**       | §3 + `scripts/doc-check.py`     |
| "Expand / shrink / rewrite / align this doc to match reality" | **rewrite**     | §4                              |
| "Turn this PLAN/任务书/thread into a stable reference doc"    | **plan-to-doc** | §5 + `templates/plan-to-doc.md` |

If the user said any of: _校对 / 检查文档 / 文档还在不在 / 文档对不对 / sync doc / 扩写 / 改写 /
把 PLAN 做成文档 / 文档并入主文档_ — this skill fires.

## 2. When to fire (trigger signals)

- User names a doc path (`docs/agenote_mcp.md`, `README.org`, etc.) and asks
  whether it's accurate, missing features, or drifting from the tool it describes.
- User added a new CLI subcommand / MCP tool / API surface and asks to update
  the matching doc; or didn't ask but you can spot the gap.
- User hands you a PLAN / 任务书 / chat thread extract and says "make this a
  reference doc" / "把这个写成文档".
- User asks "扩写 README" / "扩写说明文档" with a target audience or scope.
- A doc was last verified > 30 days ago and either the user opens a session
  involving the tool it documents, or `scripts/doc-check.py` flags drift.

**Do NOT fire** for:

- Ad-hoc grammar / typo cleanup in one paragraph (just edit it).
- Translating a doc to another language (no tool needed; user does it or
  delegates to `nano-pdf` / a translator skill if one exists).
- Generating a brand-new doc from scratch with no source material (use
  `unknown-discovery` for discovery, then `plan-to-doc` if there's a plan).

## 3. Entry point: **check** (校对 / drift 体检)

The most common entry. Three questions to answer fast:

1. Does the doc still match the tool/code/CLI/MCP it describes?
2. Does it cover the user's recent changes?
3. Are there silent rot patterns (duplicated with another doc, stale date
   stamps, links to missing files)?

**Run `scripts/doc-check.py` first.** It is the only artefact in this skill
that reads from outside the doc and reports ground truth — never trust a
L;DR summary of "looks accurate".

```bash
# 1. 体检：对照 CLI/MCP 当前实际输出 diff 文档
python3 scripts/doc-check.py /path/to/doc.md

# 2. 用 stdout 一份校对报告（也可以 --json 出 JSON 给下游消费）
python3 scripts/doc-check.py /path/to/doc.md --json
```

What `doc-check.py` knows how to detect (see `references/doc-review-checklist.md`
for the full 12-item human checklist that complements the script):

- **MCP/CLI surface drift**: if the doc names an MCP tool or CLI subcommand,
  verify it exists; if the doc lists N items, verify `agenote --help` lists the
  same N (loop the matcher the user wants).
- **Two-source-of-truth rot**: `references/2026-MM-DD-topic.md` per-session
  patterns, dates in filenames (vs. topic-based naming).
- **Self-contained violation**: doc references `~/.local/share/<agent>/tools/...`
  outside the skill tree.
- **Code-block claim drift**: any fenced command the doc asserts to "be in the
  repo" (e.g. `git rev-parse --show-toplevel`) — does the line exist?

After the script run, load `references/doc-review-checklist.md` for the human
review side (the script catches drift; the checklist catches prose-level rot).

**Always produce the report before deciding what to fix.** The report is the
input to entry point 4 (rewrite).

## 4. Entry point: **rewrite** (扩写 / 缩 / 对齐 / 合并)

Workflow:

1. **Re-read the doc** with `read_file` (NEVER trust the cached version from
   when the task started — docs rot in seconds).
2. **State the ground truth** from §3's report: here is what changed / what
   was missing.
3. **Pick a rewrite mode**:

   | Mode         | Use when                                                                             |
   | ------------ | ------------------------------------------------------------------------------------ |
   | **expand**   | Doc is too thin to cover new features (e.g. only 6 CLI subcommands listed out of 28) |
   | **contract** | Doc is bloated; user says "缩一缩" / "重点突出" / "去掉细节" — see §4.2              |
   | **align**    | Doc disagrees with reality in specific sections — targeted `patch()` edits only      |
   | **merge**    | Two docs cover overlapping ground, user wants one canonical doc                      |

   **When picking `contract`, first sample 1-2 sibling docs in the same
   `docs/` directory** to learn the local "thinness" target (e.g. a 100 KB
   gril-plan file should contract to ~10-20 KB to match siblings). User's
   intent is "look like the others", not "hit a magic number".

4. **Apply edits** with `patch()` for targeted fixes, `write_file()` for full
   rewrites. NEVER print a code-block in the chat as a substitute for editing.
5. **Re-run §3's `doc-check.py`** to prove the rewrite didn't introduce new drift.
6. **Append to revision log**: every rewrite ends with `## 修订记录` (or similar
   section) — one bullet per change with the date and what drifted. Future
   checkers grep this to find "what changed".

When in doubt between `expand` and `align`: align first (fix the wrong sections),
then expand only if the user signals more coverage is wanted.

### 4.1 Expansion-specific advice (the user's most common ask)

For `扩写 X 文档` tasks, the bias is usually "make it cover what the tool actually
does today". Recipe:

1. Run the tool's `--help` (or equivalent) and paste the verbatim output as
   the structural backbone — but **transcribe** into the doc's voice, don't
   dump raw text.
2. Cover four lenses:
   - **What** (the new feature/topic itself)
   - **When** (trigger signals — when does the user reach for this?)
   - **Why** (motivation the original doc lacked)
   - **How** (worked example using the user's own project, not an abstract one)
3. Add a "已落地修复" / "变更记录" section if the expansion is the result of
   a defect-fix batch (the user will re-reference this doc when reviewing
   the next defect batch).

### 4.2 Contract-specific advice (turning implementation history into a function spec)

When the source doc is a **gril-stage implementation plan** (long, full of
"P0-P8 阶段" / "实施前更正记录" / "gril session" / "fact_id=") and the
underlying work is **already done** (code lives in `config.org` / 蓝图 /
scripts/ 文件), `contract` is the right mode — but the user is really
asking for a **功能说明 (function spec)**, not "缩 30% 保持同等结构".

**User intent signal** (verbatim from real session, 2026-07-07):

> "我只需要一个用来说明相关功能的文档，参考其他文档的风格即可，不需要写非常多非常细，细的放到代码里面 (config.org) 解释会更好"

**Workflow** (recipe for this specific shape):

1. **Sample sibling docs first** — `wc -l docs/*.md` + read 1-2 to learn
   the local thinness target. Aim for that band, not arbitrary "30-50%".
2. **§0 决策表 + §接手必读** — **保留**(these are loaded in skill calls and
   referenced as 固定说法 like "§9.4.5 陷阱四条")
3. **§N 实施步骤 P0-P8 → §1 用法 + §3 已知陷阱** — implementation history
   is not usage. Demote step-by-step narrative; keep only the 3-4 most
   fatal pitfalls (use "see source/config.org `* <Topic>` 章节" for the rest)
4. **§验收清单 → 删** (the work is already done; the verification log
   belongs in git history, not the function spec)
5. **§X 编号保留** — agents and humans alike cite "§9.4.5" as a fixed
   phrase; renumbering breaks every cross-reference
6. **行号锚点 (blueprint.scm:1280) → 章节引用 (blueprint.scm §8.5)** —
   line numbers drift, section anchors don't
7. **代码块 ≤ 30 行** — full code lives in the source file; the doc only
   shows syntax, command, or a tiny pattern, with a pointer
8. **No backups / no "## 修订记录 (older versions)"** — those belong in
   git; the spec doc is single-version

**Anti-pattern (踩过的坑)**:

- ❌ **Cut into 11 sub-files** (`docs/<topic>/README.md` + 10 numbered
  files) — the user wanted "一个" (one) function-spec doc. Splitting is
  a _response_ you might consider, not a _goal_ the user asked for.
- ❌ **Keep "P0-P8 阶段" narrative** — that's process, not product.
  Future readers don't need to know you did it in 8 phases.
- ❌ **Invent implementation details** that aren't in the actual code
  (e.g. "live user uses PAM allow-empty-passwords #t") — the doc must
  match reality, not what the gril session thought reality was.
- ❌ **Reach for "clarify" too early** — when the user's one-line ask
  clearly maps to "function spec matching sibling docs", just go do it.
  Save `clarify` for genuinely ambiguous trade-offs (e.g. "where to put
  the backup").

**Empirical result** (2026-07-07): `docs/iso-build.md` from 110 KB / 2155
lines → 12.8 KB / 268 lines (88% reduction) in one rewrite. The resulting
doc points readers to `source/config.org` `* Live ISO` 章节 for code
detail — single source of truth preserved.

## 5. Entry point: **plan-to-doc** (PLAN / 任务书 / thread → 稳定参考文档)

The most fragile entry point — students get this wrong by treating the PLAN
as the final doc. Use `templates/plan-to-doc.md` as the skeleton.

**Workflow**:

1. **Locate the source**: PLAN.org / 任务书.md / thread transcript / chat export.
2. **Decide the audience**: future-self, other-agent, new-user, reviewer.
   Different audiences → different documents.
3. **Classify the source's structure** (it's almost always one of):
   - **Defect list / 任务书** (this is the most common — turn it into a
     "功能描述" doc with one section per fix; keep the verbatim verification
     evidence only when the user asks for it).
   - **Decision log** (multiple choices taken; audience needs "what did
     we decide and why").
   - **Workflow steps** (numbered procedures; the doc is mostly sections
     - commands).
   - **Conceptual explanation** (theory / why-things-are-this-way).
4. **Strip transient scaffolding**:
   - Timestamps → keep only meaningful "as of" markers.
   - Investigation transcripts → reduce to "verified by X" one-liners.
   - Agent reasoning → **strip entirely** (the user can't read it and you
     can't justify it later).
5. **Rewrite into the target voice**:
   - Reference doc voice = declarative, dry, third-person, command-first.
   - PLAN voice = imperative, hesitant, second-person, "let's try…" — strip
     all of that.
6. **Add provenance footer**: who wrote the source PLAN, when, what's the
   canonical source. Future readers need to know what to trust.
7. **Cross-link the source**: keep a pointer back to the original PLAN from
   the doc ("由 <task-doc> 在 <date> 提炼"), so the PLAN stays findable.

**Anti-pattern: 把 PLAN 原样搬进 docs/.** The PLAN mentions throwaway
investigation paths, agent hesitations, scratch IDs — none of which belongs
in a stable reference doc. The PLAN becomes a footnote, not the body.

## 6. Self-contained + progressive disclosure

- SKILL.md is the router (this file). Keep <500 lines.
- `scripts/doc-check.py` is the **runnable** artefact — that's the one
  thing the agent invokes at runtime.
- `references/` holds the per-topic detail (checklist, rewrite patterns,
  plan-to-doc template comments).
- `templates/` holds starting files the user copies and edits.

Backup = usable: backing up `~/.local/share/hermes/skills/productivity/doc-engineering/`
must capture `scripts/doc-check.py` too. Do not put it in
`~/.local/share/<agent>/tools/`.

## 7. Verification (same turn as any change to SKILL.md or scripts/)

When `scripts/doc-check.py` itself is modified or added, the same turn must
include a `hermes-verify-` ad-hoc verification:

1. Create N fixtures under `/tmp/hermes-verify-doc-*.md` covering: doc with
   no drift (matches CLI N=28), doc with N=27 (one missing), doc with
   non-existent MCP tool name, doc with stale date filename.
2. Print `PASS/FAIL` tally per fixture.
3. Clean up fixtures in a `try/finally`.
4. Print the scope line: "ad-hoc verification — not a test suite".

See `skill-authoring` §8 for the verification-evidence contract.

## 8. Pitfalls (real-session anti-patterns)

- **Trust doc-copy verbatim.** When the user pastes another agent's doc
  into a session and says "扩写这个", the source is just a starting point —
  it may already be wrong. Run §3 first, then rewrite.
- **Skip the date stamp.** Every reference doc needs a "as of <date>" or
  `## 修订记录` line so future checkers know when it was last verified.
- **Drop scratch commands in body.** Things like `cd /tmp/foo && agenote …`
  belong in a fenced example with the user's actual path substituted, not
  left as shell quotes.
- **Don't merge two docs without reading both.** If the user says "merge
  X and Y into Z", grep Z for any sentence also in X or Y; if you
  don't read both you'll keep the stale one and delete the correct one.
- **PLAN-to-doc pastes the agent's reasoning.** The user said this out
  loud: don't put your "I checked, here's why…" into the doc body.

## Out of scope

- Doc **translation** to another language — no skill needed; user or a
  dedicated translator skill handles it.
- Doc **infrastructure** (publishing pipelines, site generators) — that's
  `devtools/` territory (a separate skill would own it).
- Doc **linter / single-source-of-truth linting** as a _primary purpose_
  is `single-source-doc-lint` (sibling). This skill uses linting as one
  of three entry points; the other skill **owns** the linter design.
- Doc **generation from API schemas** (OpenAPI / jsonschema → markdown)
  is `devtools/` territory.

## References

- `references/doc-review-checklist.md` — 12-item human checklist complementing
  `doc-check.py` (machine-readable drift + manual prose rot = full coverage).
- `references/rewrite-patterns.md` — modes (expand/contract/align/merge) with
  worked workflows and anti-patterns.
- `references/plan-to-doc-template.md` — extended classification of source PLAN
  types (defect list / decision log / workflow steps / conceptual) and rewrite
  rules per type.
- `templates/doc-review.md` — review-report skeleton (machine + manual sections).
- `templates/plan-to-doc.md` — PLAN → reference-doc skeleton with provenance
  footer and cross-link back to source.
- `scripts/doc-check.py` — the checker; primary entry point for §3. Verified
  7/7 PASS on 2026-07-07 against `docs/agenote_mcp.md` (ad-hoc verification,
  not a test suite — see §7 and `skill-authoring` §8 for the contract).
