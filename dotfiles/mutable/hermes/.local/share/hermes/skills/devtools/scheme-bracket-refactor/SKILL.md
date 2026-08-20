---
name: scheme-bracket-refactor
description: "Convert Scheme code to R6RS square brackets."
version: 1.0.0
author: Hermes
metadata.hermes.tags: [Scheme, R6RS, Refactoring, Guile, Guix, StyleGuide]
---

# Scheme Bracket Refactor — Bulk-convert parens to R6RS brackets

When an existing Scheme/Guile codebase uses all round parens and you want
to bring it to R6RS Appendix C bracket convention (square brackets in
binding/clause positions), hand-editing is the wrong tool — the volume of
`let`/`cond`/`match`/`case` forms makes manual conversion error-prone, and
a single miscategorised form breaks the build. This skill captures the
converter technique and the subtle rules that a correct converter must
implement.

## When to Use

- Refactoring a Scheme/Guile codebase from all-parens to R6RS bracket style.
- Writing or debugging a paren→bracket conversion tool.
- Reviewing a bracket-conversion diff for correctness (what to look for).

## Prerequisites

- The target Scheme implementation must read `[]` as identical to `()`.
  **Guile does this natively** — verified with
  `guile -c '(let ([x 1]) (display x))'`, no reader flags needed.
- Confirm the target's build pipeline only relies on paren-balance, not
  paren-vs-bracket distinction. (Guile-based tools like Guix's `blue check`
  count round parens only; brackets are invisible to the counter, which is
  cosmetic — balance is preserved, the reported "pair count" just drops.)

## Compatibility note: Guix upstream

Upstream Guix uses **all round parens** as its dominant style. In the
Guix 1.5 checkout, `let` bindings with brackets appear in ~3 files (two
of which are patch diffs), and cond/match clauses with brackets are
essentially absent from `gnu/services/`. This means:

- Guix configuration code (G-exps, service definitions, `operating-system`
  fields) will load and run correctly with brackets — no functional risk.
- But bracketed code is **stylistically distinct** from surrounding Guix
  code. Decide deliberately: match upstream (all parens) or apply R6RS
  (brackets in binding positions). Don't assume one is "more correct."

## The case/match key-skip rule (the #1 conversion trap)

This is the subtle rule that a naive "bracket all clause-form children"
converter gets wrong. Three forms have a **key/expr sub-expression before
the clauses**, and that sub-expression must stay in round parens:

| Form | Structure | Key/expr handling |
|------|-----------|-------------------|
| `cond` / `guard` | `(cond clause...)` | No key — every direct child is a clause |
| `case-lambda` | `(case-lambda clause...)` | No key — every direct child is a clause |
| **`case`** | `(case key clause...)` | **key is a sub-expr, NOT a clause — stays round** |
| **`match`** | `(match expr clause...)` | **expr is a sub-expr, NOT a clause — stays round** |

Correct conversion:
```scheme
;; case: (string->symbol mode) is the KEY — stays round
(case (string->symbol mode)
  [(adopt) "--adopt"]      ;; clause → bracket
  [else ""])

;; match: x is the EXPR — stays round (even when itself parenthesised)
(match (foo x)
  [(? number?) 'num]
  [else 'other])
```

Incorrect (what a naive "bracket all children" converter produces):
```scheme
(case [string->symbol mode]    ;; WRONG — key got bracketed
  [(adopt) "--adopt"])
```

The distinction matters even when key/expr is an atom (not parenthesised):
`(match x ...)` — `x` is the expr, all following direct children are
clauses. A converter must look at the token stream to determine whether
the first child is a parenthesised expression (in which case skip it) or
an atom (in which case the children list already excludes it).

## Other rules a correct converter must implement

- **`syntax-rules`**: `(syntax-rules (literals) rule...)` — literals list
  stays round, only rules bracket. With ellipsis:
  `(syntax-rules ellipsis (literals) rule...)`.
- **`syntax-case`**: `(syntax-case expr (literals) rule...)` — skip BOTH
  expr and literals, bracket only rules.
- **`do`**: `(do (bindings) (test result...) body...)` — only the variable
  bindings bracket; the `(test result...)` clause stays round.
- **`let-values`/`let-values*`**: like `let`, but each binding is
  `[formals init]` (formals may be `(a b)`).
- **Lambda formals NEVER bracket.** `(lambda (x y) ...)` — parameter list
  is always round, even inside a bracketed `match`/`case-lambda` body.
- **named `let`**: `(let loop ([var init] ...) body...)` — the `loop`
  name and binding list structure follow regular `let` rules.

## How to Run — the converter script

Use `scripts/convert-brackets.py` (packaged with this skill):

```
python3 scripts/convert-brackets.py scm <file.scm>    # convert a .scm file → stdout
python3 scripts/convert-brackets.py org <file.org>    # convert only #+begin_src scheme blocks
```

The script does character-level scanning, correctly skipping:
- string literals `"..."` (with `\"` escapes)
- character literals `#\(` `#\)` `#\"` `#\\` etc. (critical — these look like parens)
- line comments `;...`
- block comments `#| ... |#` (nested-aware)
- datum comments `#;`
- quote/quasiquote/unquote prefixes `'` `` ` `` `,` `,@`

It applies all rules above and was validated end-to-end on:
- a 1477-line Guile project runner (430 lines changed, all let/let*/cond/match/case)
- a 2400-line Org config with 41 embedded scheme blocks
Both passed structural paren-balance check and dry-run build after conversion.

## Verification after bulk conversion

1. **Structural check**: re-run the project's paren-balance checker
   (e.g. `blue check` for Guix-configs). Must report zero imbalance.
2. **Load test**: verify the converted file still loads — e.g. `blue list`
   to confirm a runner's commands register, or `guile -c '(load "...")'`.
3. **Dry-run build**: if the file feeds a build pipeline, run the dry-run
   path (e.g. `blue --dry-run rebuild` — tangle + balance check + build
   --dry-run, no system write).
4. **Spot-check case/match**: grep for `(case ` and `(match ` and confirm
   the key/expr sub-expression is in round parens, not brackets.

## Procedure for a full project conversion

1. **Assess scope**: `grep -oE '\((let|let\*|cond|case|match|letrec|do) ' *.scm`
   per file to gauge volume. If only a handful of forms, hand-editing is
   fine; if dozens+, use the converter.
2. **Back up**: `cp file.scm file.scm.bak` (or rely on `git`).
3. **Convert**: run the script, redirect to a temp file, diff to review.
4. **Review the diff** for the case/match key-skip rule — this is the
   most common automated-conversion error.
5. **Apply**: overwrite the original only after review.
6. **Verify**: the three-step verification above.
7. **Commit per project convention** (e.g. `refactor(blueprint.scm): convert to R6RS brackets`).

## Pitfalls

- **Naive converters bracket case/match keys.** See "the #1 conversion
  trap" above. Always spot-check `(case ` and `(match ` forms in the diff.
- **Char literals `#\(` `#\)` fool naive scanners.** A regex-based
  converter that doesn't skip char literals will convert the `(` inside
  `#\(` and corrupt the code. The bundled script handles this.
- **Brackets inside strings.** `"(test [foo])"` must not be touched. The
  script skips string contents.
- **Brackets inside block comments `#| ... |#`.** Same — skipped.
- **`count-parens` cosmetic drop.** After conversion, a paren-counting
  tool reports fewer "pairs" because brackets are invisible to it. This
  is NOT a balance error — verify by checking the balance result (still
  `[OK]`), not the raw count.
- **Mixing styles mid-form.** If you hand-touch a converted form, keep
  bracket usage consistent within that form (all `cond` clauses bracket,
  or none — not some).

## References

- R6RS Appendix C — the authoritative source for which positions take
  brackets. (The companion skill `scheme-bracket-conventions` carries
  the quick-reference table; this skill adds the conversion technique
  and traps that the table alone doesn't convey.)
- Guile reader: treats `[]` and `()` as identical by default.
