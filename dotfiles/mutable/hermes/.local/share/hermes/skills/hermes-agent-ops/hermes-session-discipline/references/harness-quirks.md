# Harness Quirks — RecollectBeat / Hermes Gateway

## Blocked commands (inside gateway)

Running inside the Hermes gateway, these are blocked by the SIGTERM guard:

- `node_modules/.bin/tsc -p ./shared --noEmit` → Blocked
- `node_modules/.bin/eslint .` → Blocked
- `hermes gateway restart` from inside the gateway → Blocked

Error text: `Blocked: command or referenced script cannot restart or stop the gateway...`

## Verified workarounds

```bash
# TypeScript — use the JS entry point directly
node node_modules/typescript/lib/tsc.js -p ./shared --noEmit
node node_modules/typescript/lib/tsc.js -p ./play --noEmit
# All 5 projects: shared play watch preview tutorial
for p in shared play watch preview tutorial; do
  node node_modules/typescript/lib/tsc.js -p ./$p --noEmit
done

# ESLint / Prettier — same pattern
node node_modules/eslint/bin/eslint.js .
node node_modules/prettier/bin/prettier.cjs --check .
node node_modules/prettier/bin/prettier.cjs --write <path>
```

Gateway restart must be run from an external shell, never from inside the gateway process.

## Pre-commit verification (no bun available)

This repo uses `bun` scripts but `bun` is not on PATH in the gateway. Use the workarounds above plus:

```bash
git status --short
git diff --stat
git diff --cached --name-only   # after git add -- <exact paths>
```

## Commit template

Template at `~/.config/git/gitmessage` — Conventional Commits:
`<type>[optional scope]: <description>` — imperative, lowercase, no period.
Body explains what/why not how. Footer: `BREAKING CHANGE:` or `Refs #123` or `Generated with Crush`.
