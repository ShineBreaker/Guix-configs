---
name: hermes-session-discipline
description: Batch grilling and incremental commits under ponytail.
version: 1.0.0
metadata:
  hermes:
    tags: [grilling, commit, harness]
---

# Hermes Session Discipline

Class-level discipline for sessions where the user expects batched grilling and aggressive incremental commits, plus known Hermes gateway harness quirks. Apply whenever the user says "一次提问多个问题", "积极 commit", or the session runs under ponytail full.

## Batch Grilling

- Frontier batching: ask the entire frontier at once (3-5 questions), numbered, each with a recommended answer. Never single-question round-trips.
- Each question = `❓ **Qn** - **Title**: body` + `➡️ recommended answer`. Dispatch sub-agents for facts; don't ask the user for filesystem data.
- Recompute frontier after answers; downstream questions wait, rest of frontier proceeds.

## Commit Discipline (Conventional Commits)

1. Before any commit: `git status --short` + `git diff --stat` to confirm which hunks are complete.
2. Stage only completed paths: `git add -- <exact paths>` then verify `git diff --cached --name-only` and `git diff --cached --stat`.
3. Message format: `<type>[optional scope]: <description>` — imperative, lowercase, no period. Body explains what/why not how. Use `~/.config/git/gitmessage` template. AI-assisted commits carry a `Assisted-by: <agent> (<model>) <noreply@…>` trailer naming the **actual** agent and model — never another agent's name (e.g. a Hermes session must not write `Generated with Crush`; Crush is a different agent on this host).
4. Commit incrementally per candidate/step — one commit per deepening, not one mega-commit. Push immediately when user expects it (`--no-gpg-sign` fallback).
5. GPG-signed commits fail in the agent shell (no tty → pinentry cannot run → "signing timeout"). Have the user unlock once in their own terminal (preset-passphrase recipe: `termux-plugin-development` → `references/gpg-headless-unlock.md`; local script `~/unlock-gpg.sh`), then every commit within the cache TTL reuses it. Verify the unlock by an actual headless signature — agent cache flags (`KEYINFO`) are not proof (a wrong password still leaves them set).

## Gateway Harness Workarounds

Direct `node_modules/.bin/tsc` / `eslint` invocations are blocked by Hermes gateway SIGTERM guard. Use underlying JS entry points:

```bash
node node_modules/typescript/lib/tsc.js -p ./shared --noEmit
node node_modules/typescript/lib/tsc.js -p ./play --noEmit
node node_modules/eslint/bin/eslint.js .
node node_modules/prettier/bin/prettier.cjs --check .
node node_modules/prettier/bin/prettier.cjs --write <path>
```

`hermes gateway restart` from inside the gateway is also blocked — external shell only.

## Ponytail Interaction

- Ladder runs after understanding flow end-to-end (trace imports/usages first).
- Shortest working diff wins, but never the smallest change in the wrong place.
- Skip speculative abstractions; deletion > addition; one helper covers N call sites.

## Effort Calibration

When the user asks for more doing and less thinking:

- Keep action density high: during debug loops, prefer running the next decisive probe over extended deliberation; do not re-litigate a problem you already understood.
- Every fix ships ONE runnable check, and the check must cover the failure path (fake input must error, real input must pass). A success-only check lets a bug ship wearing a "verified" badge — and a false-success path that never exercises the real action is worse than no check at all.
