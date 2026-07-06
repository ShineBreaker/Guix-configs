---
name: diff-explain-self-review
description: "Force a post-edit walkthrough of every file changed, line by line."
version: 0.1.0
author: Hermes
metadata:
  hermes:
    tags: [codex, code-review, diff-walkthrough, self-review, scope-creep]
    related_skills: [code-reviewer, skill-authoring]
---

# Diff Explain — Self-Review

A Codex pattern (originated by Tideflow / OpenAI): after the model
finishes editing, **it must walk through every changed file and justify
each diff block in its own words** before considering the task done.

The point isn't to add a summary the user asked for. It is to catch the
thing strong models do best: silently widening scope — refactors, renames,
"harmless" abstractions, boundary tweaks that all *look* reasonable but
weren't asked for.

## When to Use

- "Explain your diff / what you just changed."
- "Did you change anything outside the task?"
- "Which lines are highest-risk and need my review first?"
- After any non-trivial edit (3+ files, >50 lines, or touching a boundary
  layer like auth, schema, public API).
- Before committing a multi-file change to a shared branch.
- Not for single-file typo fixes or one-line config tweaks (overhead > value).

## Prerequisites

- The change under review must be represented as a real, queryable diff
  (e.g. `git diff`, `git diff --cached`, or a saved patch file). The skill
  reads the diff verbatim — fabricating a diff defeats the entire purpose.
- Working repository or worktree with the post-edit state checked out.

## How to Run

1. Capture the diff through the `terminal` tool. Prefer one of:
   - `git diff` for unstaged changes.
   - `git diff --cached` for staged changes.
   - `git diff HEAD~1` for the last commit (after committing).
   - `git diff <base>...HEAD` for a branch comparison.
2. Feed the diff (or the diff path) to the model via a prompt that
   contains the six Question Block below, verbatim or paraphrased.
3. Read the model's answer with the **Anchored Reading** rubric in §6.
   Any answer that hand-waves files ("looks good", "minor cleanup") is
   a fail signal — re-prompt with "list every changed file, one by one."
4. Optionally: cross-check claimed scope ("only changed X") against the
   real diff with `git diff --stat` to expose silent drift.

## Quick Reference

- **Trigger phrase (paste verbatim into the next LLM turn after editing):**
  > "Walk me through every file you changed in this turn, one by one: why
  > this block, what problem it solves, what you changed *outside* the
  > original task, and which lines are highest-risk for me to review?"
- **Six Questions** every diff-walkthrough answer must address.
- **Anchored Reading** rubric: each claim must cite `file:line`.
- **Drift check:** compare claimed files-touched vs `git diff --stat`.

## Procedure

After completing any non-trivial code change, run this exact sequence
**before** reporting success to the user. Do not skip steps — the
walkthrough is the deliverable, not the diff itself.

1. **Snapshot the diff.** Invoke through the `terminal` tool:

   ```bash
   git diff --stat                  # file-level summary (cheap drift check)
   git diff                         # or: --cached, HEAD~1, <base>...HEAD
   ```

   Save the full diff to a file (`/tmp/diff-<task>.patch`) if it is more
   than a screen tall — re-pasting raw diffs into the prompt eats context
   budget that should go to the review.

2. **Issue the Six Questions** (use this prompt, verbatim or paraphrased,
   in the same turn as the change — not the next session):

   ```
   Please walk through the diff you just produced, file by file. For each
   changed file, answer:

   1. Why this file? — what part of the original task requires touching it?
   2. What is the *minimal* change that satisfies that requirement?
   3. Did you change anything *outside* the task? (renames, formatting,
      "while I'm here" cleanups, speculative refactors, abstracting a
      helper that didn't need it) — list each, justify why, and admit
      which are pure taste.
   4. For each affected block, classify it: required / taste / risky.
   5. Which 3-5 lines should the user read FIRST to catch the highest-
      risk semantics? (auth boundaries, error paths, async cancellations,
      schema migrations, public-API signatures, lock acquisition order.)
   6. Anything you considered and *didn't* change, but now worry you should
      have — open questions you want flagged.
   ```

3. **Anchored Reading.** Verify the model's answer:
   - Every file claim references a real path (`path/to/file.py:42`,
     not "the config file").
   - Every "I changed X" is traceable to a diff hunk. Cross-check against
     the saved diff.
   - If the model groups multiple files under "general cleanup" without
     naming them, **reject the answer and re-prompt** — this is exactly
     the scope-creep signal the walkthrough exists to catch.

4. **Drift check.** Compare what the model says it touched against what
   was actually touched:

   ```bash
   git diff --name-only            # actual files changed
   ```

   Any file in `--name-only` that the walkthrough **did not mention** is
   a silent scope expansion. Stop and ask the user before continuing.

5. **Decide per line / per hunk.** Apply one of four actions:
   - **Keep** — required and minimal.
   - **Keep with note** — required but worth a comment in the PR or a
     heads-up to the user.
   - **Revert** — taste, not asked for, and not worth the diff noise.
   - **Discuss with user** — risky, ambiguous, or "should I have done
     this?" callers.

   Strong models default to "Keep" almost always. Push back: taste
   reverts are nearly always cheaper than reading what they wrote.

6. **Surface the result.** Tell the user which lines they should read
   first, in the order the model recommended (highest-risk first). Don't
   re-paste the diff — the user has it. Don't recap what changed in
   prose — the model already did, and the user wants the call-to-action
   ("review lines X-Y first").

## Pitfalls

- **The walkthrough becomes a victory lap.** If the answer reads like a
  PR description ("refactored X for clarity, cleaned up Y, hardened Z"),
  it is doing the opposite of what it should. Reject and re-prompt with
  "be specific about *which* lines are taste and which were asked for."
- **Fabricating a diff.** The walkthrough has no value if the diff is
  invented. Always start from `git diff` (or equivalent). If no VCS,
  the skill doesn't apply — do the equivalent manually.
- **"I didn't change anything outside the task."** This single sentence
  is the most common lie the model tells itself. Treat it as a smell,
  not an answer. The Six Questions force enumeration, which makes the
  lie obvious.
- **Skipping on tiny edits.** A 3-line fix in a config file is below
  the threshold. Spending more time reviewing than editing wastes the
  user's trust — judge by file count and blast radius, not a fixed
  line count.
- **Batching the walkthrough into a final summary.** The walkthrough
  must happen in the **same turn** as the change, or the model will
  have forgotten the context for which lines were taste vs required.
  Don't defer it to the final assistant message.
- **Anchored Reading drift.** If the model cites `file.py:42` and that
  line isn't in the diff, it's hallucinating an answer to look thorough.
  Always cross-check with `git diff` or `read_file`.

## Verification

Run this after every non-trivial edit, **before** telling the user
"done":

```bash
git diff --stat | tail -n +2 | wc -l     # how many files actually changed
```

Then check, by hand or with a short script: every file in that count
must appear in the model's walkthrough answer by exact path. If any
file is missing, the walkthrough failed — re-run with the Six Questions,
do not declare done.

Ad-hoc verify scope, not a test suite: this is a self-review protocol
the agent runs in-process; the bar is "the user can trust the
walkthrough caught silent scope expansion", not "CI is green."
