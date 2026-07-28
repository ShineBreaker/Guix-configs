---
name: writing-gates
description: "Write/maintain per-project pi-gate authority boundaries (.agents/anchors.json): freeze commands, protect paths/globs, soft hints, command rewrites. Triggers: project gate, freeze a command, protect a folder, block rm/deploy/kubectl, pi-gate, frozen_commands, frozen_paths, frozen_globs, path_hints, rewrite, ratchet, meta-frozen, anchors.json."
version: 1.0
license: MIT
metadata:
  hermes:
    tags: [pi-gate, gate, anchors, authority-boundary, safety, guardrail]
---

# Writing Gates — per-project authority boundaries for pi-gate

pi-gate is the omp extension that intercepts `bash` / `write` / `edit` tool calls. This skill tells you **how to choose and write a project-level gate** so the guardrails fit the repo you are actually working in, instead of relying only on the global rules.

## The layered model (read this first)

Restrictions stack in three layers. Each layer can only **add** restrictions — never remove what a lower layer enforces (ratchet). Arrays are unioned; maps shallow-merge with the **nearer** layer winning.

| Layer         | Where                                 | Who edits                    | Scope                       |
| ------------- | ------------------------------------- | ---------------------------- | --------------------------- |
| 1. Code floor | `pi-gate/index.ts`                    | nobody (compiled in)         | universal, every project    |
| 2. Global     | `~/.config/agents/anchors.json`       | human only (**meta-frozen**) | this machine, every project |
| 3. Project    | `<project-root>/.agents/anchors.json` | **you, via this skill**      | one repo                    |

**Code floor (always on, do NOT duplicate in config):** `sudo`; interactive editors/pagers/REPLs (`vim`/`less`/`man`/bare `python`/`node`); `git add -p`, `git rebase -i`, `git commit` without `-m`; destructive `rm` (`rm -rf`, or `rm` targeting `/`, `~`, `$HOME`, `*`, `.`, `..`) — plain `rm` only gets a soft hint to use `trash`/`mv`.

Because the floor and global layers always apply, your job in a project gate is to encode what is **specific to this repo**: its dangerous commands, its protected directories, its "remember to run X after editing" reminders.

## Where the file lives and how it resolves

- Path: `<project-root>/.agents/anchors.json`. pi-gate walks **up from the cwd to the git root** and loads every `.agents/anchors.json` it finds (so a monorepo can have a root gate plus per-package gates; nearer wins for maps).
- **Relative paths/globs/hints resolve against the layer's own root** (the dir containing that `.agents/`), not the cwd. So an ancestor gate's `tmp/` means _that ancestor's_ `tmp/`. `~/…` always expands to the home dir.
- Discovery is by **file presence** — no registration needed. It takes effect in the **next session** (the running extension is loaded once at startup).

## Decision procedure — which mechanism?

Ask what you actually want to happen, then pick the narrowest tool:

| You want…                                                                              | Use                      | Blocking?          | Matches on                                                  |
| -------------------------------------------------------------------------------------- | ------------------------ | ------------------ | ----------------------------------------------------------- |
| A command never to run (`make deploy`, `kubectl delete`, `blue rebuild`)               | `frozen_commands`        | ✅ hard block      | **substring** of the command                                |
| A directory/file off-limits to write/edit (`infra/`, `migrations/`, `~/.config/`)      | `frozen_paths`           | ✅ hard block      | path **prefix** (relative to layer root) OR basename suffix |
| A file _pattern_ off-limits (`*.pem`, `secrets/**`, `**/*.lock`)                       | `frozen_globs`           | ✅ hard block      | glob vs relative path (`/` present) or basename (no `/`)    |
| A command that's fine but has a preferred form (`guix home reconfigure` → `blue home`) | `redirect_conventions`   | ❌ notify only     | substring                                                   |
| To silently swap a tool (`npm`→`bun`, `yarn`→`pnpm`)                                   | `rewrite`                | ❌ mutates command | token at command-start, word-boundary                       |
| "After editing files under X, remember Y" (`dotfiles/` → run `blue home`)              | `path_hints`             | ❌ notify only     | path prefix (relative to layer root)                        |
| Stop the built-in `npm→pnpm` / `pip→uv` swap for this repo                             | `builtin_rewrite: false` | —                  | —                                                           |

### Choosing well — rules of thumb

- **Prefer the softest tool that is safe.** A hard block that fires on legitimate work trains people to delete the gate. Use `redirect_conventions`/`path_hints` for conventions, `frozen_*` only for genuinely dangerous or irreversible operations.
- **`frozen_commands` is substring matching — use multi-word entries.** `"blue rebuild"` is safe; a bare single word like `"rm"` would also hit `confi`**`rm`**, `fo`**`rm`**. Single-token, word-boundary-sensitive rules (like `rm`) belong in the **code floor**, not config. If you need to block a one-word command, make the entry as specific as you can (`"deploy.sh"`, `"kubectl delete"`) and accept it is a substring.
- **`--dry-run` escapes `frozen_commands`** by design (verification stays possible). Don't rely on a frozen entry to block dry-run invocations.
- **Paths: prefix vs suffix.** `tmp/` blocks anything under the layer's `tmp/`. `channel.lock` (no slash) blocks any path _ending_ in `channel.lock`. Use `frozen_globs` when you need `**`/`*` semantics.
- **`rewrite` runs after the built-in swaps and overrides them per token**: setting `rewrite: {npm: bun}` makes `npm`→`bun` and suppresses the built-in `npm→pnpm`.
- Document the _reason_ in `_comment`. Future agents (and humans) must tell safety rules from stale ones.

## Security invariants (do not try to work around these)

- **Ratchet:** your project gate cannot un-freeze `sudo`, the interactive-command bans, the `rm` protection, or anything in the global file. Adding `"frozen_commands": []` does nothing to lower layers.
- **The global `~/.config/agents/anchors.json` is meta-frozen** — pi-gate blocks agents from editing it. If a rule belongs everywhere on this machine, ask a human to add it there.
- **Your project gate is agent-writable by default** (that is the point of this skill). To lock a project gate so agents cannot weaken it, add `"_meta_frozen": true` — pi-gate will then refuse agent edits to that file too. Use this for rules a human has ratified (e.g. production-deploy bans).
- Sensitive-content detection (API keys, private keys, tokens) always runs on `write`/`edit` content regardless of gates.

## Schema reference

```jsonc
{
  "_comment": "why this gate exists; what each block protects",
  "_meta_frozen": false, // true ⇒ agents cannot edit this file
  "frozen_commands": ["make deploy", "kubectl delete"], // substring; hard block
  "frozen_paths": ["infra/", "~/.config/", "channel.lock"], // prefix or basename-suffix; hard block
  "frozen_globs": ["secrets/**", "*.pem"], // glob; hard block
  "redirect_conventions": { "guix home reconfigure": "use blue home" }, // substring; notify
  "rewrite": { "npm": "bun" }, // token→token at command start; mutates; overrides builtin
  "path_hints": { "dotfiles/": "run `blue home` after editing" }, // prefix; notify
  "builtin_rewrite": true, // false ⇒ disable built-in npm→pnpm / pip→uv
  "human_only_actions": ["make deploy (pushes to prod)"], // docs for reviewer/skill
  "anchor_measurements": ["ci green", "git diff non-empty"], // docs: done-criteria
}
```

All fields are optional; omit what you don't need.

## Examples

**Node project that uses Bun, with a protected CI dir:**

```json
{
  "_comment": "Bun repo; CI workflows must not be edited by agents.",
  "rewrite": { "npm": "bun" },
  "builtin_rewrite": false,
  "frozen_globs": [".github/workflows/**"],
  "path_hints": {
    "src/generated/": "generated code — edit the schema and re-run codegen, not these files"
  }
}
```

**Production-infra repo (lock the deploy ban):**

```json
{
  "_comment": "Terraform/prod. Deploy is human-only; ratified, so locked.",
  "_meta_frozen": true,
  "frozen_commands": [
    "terraform apply",
    "terraform destroy",
    "kubectl delete",
    "./deploy.sh"
  ],
  "frozen_paths": ["prod/", "*.tfstate", "*.tfvars"],
  "human_only_actions": ["terraform apply/destroy", "any change under prod/"]
}
```

**This repo (Guix-configs) — the live example at `.agents/anchors.json`:**
blue/guix-system command bans, `tmp/` + `channel.lock` + `~/.config/`/`~/.local/` path bans, `guix home reconfigure`→`blue home` redirect, and `dotfiles/`/`source/` path hints. Read it as a worked reference.

## Checklist before you finish

1. Did I pick the softest mechanism that is still safe?
2. Are `frozen_commands` entries multi-word/specific (no bare single tokens)?
3. Do relative paths mean what I think (resolved against _this_ repo root)?
4. Did I write a `_comment` explaining each restriction?
5. If a human ratified these rules, did I add `_meta_frozen: true`?
6. Did I remember it activates next session, and verify with a quick probe (e.g. try the command in a throwaway run / or unit-test the exported `checkBashCommand`/`checkProtectedPath`)?
