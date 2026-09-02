---
name: ai-codebase-hygiene
description: Keep AI-generated codebases maintainable and non-decaying.
version: 0.1.0
license: MIT
author: Hermes
metadata:
  hermes:
    tags: [AI-Coding, Testing, Maintainability, Rules, CI]
    related_skills: [codebase-design, code-reviewer]
---

# AI Codebase Hygiene

A governance method for codebases written almost entirely by AI: keep them
iterative, maintainable, and non-decaying over years. It does NOT automate
anything by itself — it defines what the engineer decides, what the AI
executes and self-verifies, and where the mandatory checkpoints sit.
Dependencies: a git repo and a CI runner; nothing else.

Calibration from one production project (a Swift app, distilled from the
author's write-up at v1.13): ~110k lines production code, ~73k lines test
code (~66%), 3347 XCTests, 1000+ `fix` commits of which 900+ shipped with
tests. These numbers are one project's evidence, not targets.

Core stance: **AI writes the code, AI tests the code; the engineer owns
judgment** — architecture, boundaries, restraint, and the rules that keep
AI output consistent over time.

## When to Use

- "AI 写的代码越来越乱 / the AI-coded project is decaying"
- Starting a project that AI will write end-to-end; designing its guardrails
- Auditing whether an AI-heavy repo can survive long-term iteration
- Deciding what tests / rules / CI checks an AI coding workflow needs
- Multi-agent development that needs a stable shared foundation

## Prerequisites

- A git repository (commit history is part of the governance record).
- CI (e.g. GitHub Actions) for the clean-machine re-run.
- Run all commands through the `terminal` tool.

## How to Run

Not a script — a standing governance loop applied at five moments:

| Moment | Step |
| --- | --- |
| After v1 runs | 1 — architecture contract |
| Every bug | 2 — fix + regression + same-class sweep + rule |
| Every feature request | 3 — restraint gate |
| Every release | 4 — state-by-state verification |
| Periodically | 5 — prune rules, refresh checks |

## Quick Reference

- Test-code ratio heuristic: ~60–70% of production code (calibration: 73k/110k). A sanity signal, not a goal.
- Bug loop: fix → regression test that fails on old code → sweep sibling call sites → write the *why* into rules.
- Restraint gate: no new resident overhead; no new privileges/entitlements; no new setting when a sane default exists; updates/cleanup never scope-creep on "one more possibility".
- Five release states verified separately: local code / git commits / signed artifact / live files / what users actually receive.
- Green CI ≠ shipped. (Real failure seen: source correct, server still serving the old file.)
- Rules are split per module and loaded only when touching that module; recurring checks graduate into skills.

## Procedure

1. **Architecture is the engineer's call.** Layering, what goes where, which
   abstractions get shared — still human judgment when AI writes every line.
   Right after v1 runs: argue it out with your strongest model, then record
   it in living documents that follow the project and get revised as it
   evolves. Read them via `read_file` whenever a design question reopens.

2. **AI tests AI.** Unit tests are the backbone. Do not put humans into the
   test-verification loop — it is the slowest stage. The easy cases write
   themselves; budget effort for the "looks right, is actually wrong" class:
   - state changed after a scan/computation completed;
   - a process check failed;
   - a command returned success but the app never actually updated;
   - a stale late-arriving task overwrote a newer result.

3. **Bug loop — leave more than the fix.** For every bug:
   1. Fix it.
   2. Add a regression test that fails against the old code.
   3. Sweep the same-class paths (`search_files` for sibling call sites).
   4. Write *why* the change was made into the module's rules file.
   Much of a mature suite is real-user incidents turned into tests; that
   accumulated test + rule corpus is the project's most valuable asset.

4. **Rules files carry the why.** Tests remember inputs and results; they do
   not remember why an approach was abandoned. Rules record feature
   boundaries, historical reasons, and untouchables — e.g. why a class of
   files must rather be missed than auto-deleted; why seemingly duplicate
   components must not be merged; which system data the tool must not own.
   - One rules file per module; load only the relevant one when editing that
     module (context economy).
   - Recurring checks graduate into skills, e.g. `bugs` (find same-class
     issues from past fixes), `design-system-review` (UI decay),
     `release` (signing, notarization, remote files, update chain).
   - Keep them fresh: remove logic for behavior that no longer exists.

5. **Restraint — build less.** AI makes a new setting / compatibility
   branch / background listener take minutes; the residual state and
   maintenance cost is the biggest rot source. Gate every feature request:
   no resident overhead, no new system privileges, no new setting when a
   reasonable default exists, no widening of update/cleanup scope. Many
   features developers think matter, users never touch. 如无必要，勿增实体.

6. **CI is the final net — and a consistency checker.** After code runs and
   tests are green, it is still not done:
   - Keep cross-artifact consistency checks: all supported languages,
     generated website, Appcast/update feed, project files, public
     deployment files. One command runs everything (theirs: `make verify`).
   - CI re-runs the suite on a clean cloud machine.
   - At release, local code, git commits, signed package, live files, and
     the update users actually receive are five different states — confirm
     each one separately.

7. **Checkpoints, not intervention.** The engineer does not touch the
   execution flow: the AI executes each step, self-verifies, and resolves
   its own errors. The engineer's job is placing checkpoints where the AI
   must stop and produce an explicit verification result before proceeding,
   and iterating the rules so checks evolve in sync with the code.

## Pitfalls

- **Green checkmarks end too early.** Verify the deployed/live state, not
  just the repo — a correct source tree can coexist with a stale served file.
- **Chasing the numbers** (3347 tests, 66% ratio) misses the point; the
  metric is coverage of deceptive failure modes.
- **Rules bloat.** One giant rules file eats context on every task — split
  per module, load on demand.
- **Human QA on AI output** reintroduces the slowest stage. Review judgment
  and boundaries, not each test run.
- **Scope rot is silent.** Each individually-reasonable setting or branch
  compounds into unmaintainable state.
- **Stale rules are worse than none** — an outdated "never touch X" blocks
  correct changes. Prune whenever behavior changes.

## Verification

The loop is alive if (a) the aggregate check passes on a clean checkout and
(b) recent fixes carry regression tests:

```bash
git log --oneline --grep='^fix' | wc -l        # fix-commit volume
git log --grep='^fix' --name-only -5           # eyeball: recent fixes touch test files
make verify                                     # or the repo's aggregate check; must exit 0
```
