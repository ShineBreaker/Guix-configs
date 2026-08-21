---
name: scheme-bracket-conventions
description: "Use for R6RS Appendix C square-bracket placement and refactor conversion in Scheme."
version: 0.1.0
author: Hermes
metadata.hermes.tags: [Scheme, R6RS, StyleGuide, Syntax]
---

# R6RS Square-Bracket Conventions

R6RS Appendix C specifies when square brackets `[...]` are conventionally
used in place of parentheses `(...)` to improve readability. Brackets are
syntactically identical to parens but signal binding/clause contexts to
readers. This skill lists the specific syntactic forms where bracket use
is idiomatic per the standard.

## When to Use

- Writing or refactoring Scheme code and deciding `[]` vs `()`.
- Reviewing Scheme code for idiomatic bracket usage.
- Teaching or explaining Scheme style conventions.

## Prerequisites

- None (pure reference skill; stdlib only).

## How to Run

This is a reference skill. Consult the Quick Reference and Procedure when
writing or reviewing Scheme code. No scripts to invoke.

## Quick Reference

Forms where `[...]` replaces `(...)` by R6RS convention:

| Form | Bracket usage |
|------|---------------|
| `cond` clause | `[test expr1 ...]`, `[test => expr]`, `[else expr1 expr2 ...]` |
| `case` clause | `[(datum1 ...) expr1 expr2 ...]`, `[else expr1 expr2 ...]` |
| `let` / `let*` / `letrec` / `letrec*` bindings | `([var1 init1] ...)` |
| `let-values` / `let-values*` mv-bindings | `([formals1 init1] ...)` |
| `syntax-rules` rule | `[srpattern template]` |
| `identifier-syntax` clause | `[id1 template1]`, `[(set! id2 pattern) template2]` |
| `do` variable bindings | `([var1 init1 step1] ...)` |
| `case-lambda` clause | `[formals body]` |
| `guard` clause | `[test expr1 ...]`, `[test => expr]`, `[else expr1 expr2 ...]` |
| `syntax-case` rule | `[pattern output-expr]`, `[pattern fender output-expr]` |

## Procedure

1. **Identify the syntactic form.** Determine whether the form is one
   listed in Quick Reference (e.g., `cond`, `let`, `syntax-case`).
2. **Check if brackets are conventional.** If the form appears in the
   table, square brackets are the idiomatic choice for the binding/clause
   portion.
3. **Use brackets consistently.** Within a single form, use brackets for
   designated clauses and regular parens for function calls and other
   nested expressions.
4. **Don't force it.** If a form is not in the list, use parentheses.
   Brackets are not a universal readability tool -- only conventional in
   the specific positions listed.

## Pitfalls

- **Brackets are not required.** Using parens everywhere is always valid;
  brackets are purely a convention.
- **Not all Schemes follow this.** R6RS is the source of this convention;
  R5RS and R7RS do not specify it. Some Scheme styles avoid brackets
  entirely.
- **Don't mix bracket styles within one form.** If you use brackets for
  `cond` clauses, use them for all clauses in that `cond`, not some.
- **Brackets in data literals differ.** `[1 2 3]` and `#(1 2 3)` have
  different semantics. Brackets used inside a syntactic form's
  *designated positions* are convention; brackets used for data are not
  covered by this appendix.

## Verification

Read the code you've written. For each `cond`, `let`, `case`, `syntax-case`,
`syntax-rules`, `do`, `guard`, `case-lambda`, `identifier-syntax`,
`let-values`, or `let-values*` form:
- Does it use brackets in the positions listed in Quick Reference?
- Are function calls still in regular parentheses?

If yes, the code follows R6RS Appendix C conventions.

## Refactor mode (bulk conversion, from scheme-bracket-refactor)

Includes refactor mode: batch-convert all-parens code via `scripts/convert-brackets.py` (`scm`/`org` modes, char-level scan skipping strings/comments/char-literals); trap — `case`/`match` key/expr stays `()` (only clauses → `[]`); verify with paren-balance + `guile -c '(load ...)'` + spot-check `case`/`match` keys.
