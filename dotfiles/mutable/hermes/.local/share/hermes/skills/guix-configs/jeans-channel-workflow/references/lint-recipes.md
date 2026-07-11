# jeans lint-fix recipes — `guix lint` warning classes from the cron auto-fix workflow

Scope: concrete lint warnings observed in `~/Projects/Config/jeans` during
cron auto-fix sessions (especially the `jeans-issue-fixer` cron job), with
the exact patch hunks and re-check commands. Pairs with
`jeans-channel-workflow` §3.

Authoritative baseline: Guix `9e068cc03bfacbbcd199f3618fcf360df3f368e0`.
Re-verify `guix lint -l` on the host before trusting these recipes — checker
names drift between Guix commits.

---

## Recipe 1: `wrap-program` package missing `bash-minimal` in inputs

**Checker:** `wrapper-inputs`
**Affected class:** Any `-bin` / Electron / .deb-wrap package using
`wrap-program` after patchelf. The most common silent failure introduced by
`scripts/check-updates/update_versions.py` since it only edits `version`
and `base32` and does NOT touch `inputs`.

### Before

```scheme
;; modules/jeans/packages/agent.scm, zcode@3.3.0
(arguments
 (list
  #:tests? #f
  #:validate-runpath? #f
  #:strip-binaries? #f
  ...
  (add-after 'install-icons 'wrap-program
    (lambda* (#:key inputs outputs #:allow-other-keys)
      ...
      (wrap-program (string-append out "/bin/zcode")
        `("LD_LIBRARY_PATH" prefix ...))))))
(native-inputs (list binutils patchelf tar xz))
(inputs `(("alsa-lib" ,alsa-lib)
          ("at-spi2-core" ,at-spi2-core)
          ("cups" ,cups)
          ...))
```

Lint output:

```
modules/jeans/packages/agent.scm:904:2: zcode@3.3.0: 使用 'wrap-program' 时应在 'inputs' 中包含 "bash-minimal"
```

### Fix

Insert one line in the quasiquote alist at alphabetical position (`at-spi2-core`
is before `bash-minimal`; `bash-minimal` comes before `cups`).

```diff
     (inputs `(("alsa-lib" ,alsa-lib)
               ("at-spi2-core" ,at-spi2-core)
+              ("bash-minimal" ,bash-minimal)
               ("cups" ,cups)
```

`bash-minimal` is already imported via `#:use-module (gnu packages bash)` in
`agent.scm` (line 13) — 13 packages in the same file use it. Pattern matches
the existing label conventions from AGENTS.md "input label 规范".

### Re-check

```bash
guix lint -c wrapper-inputs -L modules zcode
guix build -L modules -e '(@ (jeans packages agent) zcode)' --no-grafts
guix repl -L modules /dev/stdin <<< '(use-modules (jeans)) (display "OK\n")'
```

All three must exit 0. `wrapper-inputs` should report no warning.

---

## Recipe 2: description missing trailing period

**Checker:** `description`
**Affected class:** New or auto-updated packages where `(description "...")`
ends with a parenthetical like `(revert guix patch)` rather than a sentence.
Lint's sentence-terminator heuristic flags this even when the string's first
sentence ended with `.`.

### Variant A — single-string description

`opentabletdriver-udev-rules@0.6.7`:

```diff
-    (description "Open source, cross-platform, user-mode tablet driver")
+    (description "Open source, cross-platform, user-mode tablet driver.")
```

### Variant B — multi-line description with trailing parenthetical

`librewolf-nongnu@152.0.4-1` (multi-line `(description "...")` block ending
in `(revert guix patch)`):

```diff
        (description
         "LibreWolf is designed to increase protection against tracking and
    fingerprinting techniques, while also including a few security improvements.
    This is achieved through our privacy and security oriented settings and
    patches.  LibreWolf also aims to remove all the telemetry, data collection and
-   annoyances, as well as disabling anti-freedom features like DRM. (revert guix patch)")
+   annoyances, as well as disabling anti-freedom features like DRM. (revert guix patch).
+This package reverts the upstream Guix patch.")
```

Why not just add `.` inside the parenthetical (revert guix patch.)? Because the
parenthetical is meant to read as an inline parenthetical, not a sentence by
itself. Appending a real sentence after it reads better and lint is happy.

### Re-check

```bash
guix lint -c description -L modules <pkg>
```

---

## Recipe 3: `coreutils` → `coreutils-minimal` (DON'T apply for `-bin` packages)

**Checker:** `inputs-should-be-minimal`
**Affected class:** Wide.

`crush-bin@0.83.0` (and many other -bin packages) report this. Tempting to
auto-fix but **wrong**: the install phase uses
`(mkdir-p ...)` / `(copy-file ...)` / `(invoke "cp" ...)` / `find-files`
etc — operations that are coreutils itself, not GNU userland shell tools.
Replacing with `coreutils-minimal` would silently break install phase on
build dependencies like cp, install, find, mv.

**Verdict:** keep `coreutils` in `(inputs ...)` of -bin packages. Lint noise
must be accepted.

---

## Recipe 4: AGENTS.md drift — `source/channel.lock` does not exist

**Not a lint warning but a documented-path drift that catches new agents.**

`AGENTS.md` (project context, auto-injected) describes a layout including
`source/channel.lock`. The actual repository has only:

- `.guix-channel` (root, standard Guix channel manifest — declares
  `(name jeans)` + `nonguix` dependency + `directory "modules"`)
- No `source/` directory
- No `channel.lock` file

The blueprint (`blueprint.scm`) and `blue` CLI use `-L modules` + the
`.guix-channel` declaration. There is NO need to recreate `source/channel.lock`.

**If you ever search for it** during auto-fix, that's why it's missing —
don't add a fake `source/` directory to match AGENTS.md; correct fix would
be a future AGENTS.md cleanup (not in scope for a lint-fix cron run).

---

## Recipe 5: Text-level paren delta is misleading — what to verify instead

Counting `(` vs `)` as bytes in `browser.scm`:

```
text ( count: 398
text ) count: 392
text diff:    6
```

This 6-character delta is **HEAD state** (pre-existing in repo). Comparing
the byte count between current working tree and
`git show HEAD:<file>` confirmed identical 6 — meaning the
description-string edits I made did NOT introduce the delta. The `(` in
`'https://services.addons.mozilla.org/api/v4/...'` and
`(revert guix patch)` literals account for it.

### The only trustworthy verification chain

1. **`guix repl -L modules /dev/stdin` + `(use-modules (jeans))`** —
   must print the sentinel `OK` marker; this exercises every package file
   to compile + bind to its public interface.
2. **`guix build -L modules -e '(@ (jeans packages <file>) <pkg>)'`** —
   must return 0; this proves the specific patched package's derivation
   compiles. **Do not** rely on `guix build -n` alone — `-n` skips the
   real fixed-output validation.
3. **`guix lint -n -L modules <pkg>`** with a filter that drops the
   `substitute*` "line too long" noise, the `search-path %load-path`
   relative-path false positives, and the auto-generated-tar noise (see
   skill §5.2 for the exact filter regex).

All three green = real verification. Byte-counting `(`, `)` is not.

### Ad-hoc verification script template

For cron auto-fix, when the system asks for fresh passing verification
evidence, write a `/tmp/hermes-verify-*.sh` script that runs all three
above + a `git diff` self-check. Then delete the script + log after.
Keep the script under 60 lines. Example: see the 5-step template inline
in the SKILL.md §3.4.

---

## Quick-reference checker table (Guix 9e068cc baseline)

| Warning text (zh)                                  | Checker               | Auto-fix? | Notes                                                                   |
| -------------------------------------------------- | --------------------- | --------- | ----------------------------------------------------------------------- |
| 应在 'inputs' 中包含 "bash-minimal"                | `wrapper-inputs`      | ✅        | §Recipe 1                                                              |
| 输入标签与包名不匹配                               | `input-labels`        | ✅        | Use quasiquote alist `("foo:lib" ,foo "lib")` — AGENTS.md has the table |
| description should end with a period               | `description`         | ✅        | §Recipe 2                                                              |
| coreutils 可能应改 -minimal                         | `inputs-should-be-minimal` | ⚠ skip | §Recipe 3 — false positive for -bin packages                            |
| 第 N 行过长                                        | `formatting`          | ❌        | `substitute*` patterns legitimately long; cosmetic noise              |
| 解析为相对于当前目录                               | (carry-over)          | ❌        | `search-path` false-positive — skill §5.2                              |
| 自动生成的 tar 包 / 源文件名应包含包名            | `source-unstable-tarball` | ❌    | GitHub archive format is intentional; conflicts with §1.1 url-fetch     |
| 补丁文件名应以包名开头 / 补丁缺少注释              | `patch-file-names` / `patch-headers` | ⚠ manual | Cosmetic; rename + add header together, breaks referrer paths       |

**Cron policy:** Auto-fix only the ✅ rows; report the ⚠ rows but don't touch;
ignore ❌ entirely.

---

## Verification of this skill (2026-07-11)

These recipes were extracted from a real cron auto-fix session that touched
3 files (zcode / librewolf-nongnu / opentabletdriver-udev-rules) and
achieved lint green on all three before being deleted from the working
tree by the user. The 5-step verification chain (repl / lint / derivation
/ byte-diff / git diff self-check) was the working pattern.
