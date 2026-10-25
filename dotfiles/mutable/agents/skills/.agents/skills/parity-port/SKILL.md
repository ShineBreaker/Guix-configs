---
name: parity-port
version: 1.0.0
author: Hermes Agent
license: MIT
description: "跨语言移植 helper 并保证字节级一致行为（对拍验证）。触发：把工具函数移植到另一语言 / 要求两实现输出逐字节一致 / 写对拍测试——任一出现即调用。"
metadata:
  hermes:
    tags: [porting, parity-testing, rust, shell]
    related_skills: []
---

# Parity Port — rewrite helpers without changing behavior

## When to Use

Rewriting a helper, script, or small tool in another language where the
contract is "same behavior, new implementation" — especially shell/python
helpers moving to Rust. Load it before starting the port, not after diverging.

Goal: a rewrite (usually shell/python -> Rust) that is byte-identical in
file outcomes, stdout, stderr, exit codes, and subprocess invocations.

## Workflow

1. Read the original end to end before writing anything. List every branch,
   every external command, every exit path.
2. Verify uncertain shell semantics empirically with the real shell/grep/sed
   before mirroring them — never trust memory of edge behavior. Record each
   confirmed quirk in `references/shell-quirks.md` style (rule + mechanism).
3. Write the port with `#![forbid(unsafe_code)]` (or the equivalent strictness
   for the target language); prefer subprocesses for process control.
4. Build a differential harness: identical fixture trees -> run original and
   port side by side -> diff file trees, stdout, stderr, exit codes, and
   stub-call logs. Normalize sandbox paths; filter ONLY documented,
   locale-specific divergences (never filter real output).
5. Add unit tests for pure matchers/helpers alongside the harness.
6. Iterate until the harness is fully green, then commit. Keep the original
   as fallback (QML `rust || script`, or equivalent) until rollout proves out.

## Rules

- Mirror file-write permission semantics per operation, not per file: `sed -i`
  is temp-file + rename (needs only directory permission, preserves mode);
  `awk > tmp && mv` gives a FRESH mode; `>>` appends (needs file write
  permission and fails on read-only files exactly like the original).
  Collapsing them into one write call is a parity bug on read-only trees.
- Environment lookups (HOME, *_CONFIG) must stay dynamic so tests can sandbox
  them; never bake paths at build time.
- External tools that are best-effort in the original (`|| true`, unchecked
  status) stay best-effort in the port. Test them with logging stubs on PATH
  and diff the call logs — do not skip the invocation comparison.
- When the upstream renames identifiers mid-port, rebase the port onto the
  new naming and re-run the full harness; do not ship a stale-named binary.
- Drop ports whose target was deleted upstream and has no callers instead of
  keeping them compiling. Deletion over maintenance.
- Integration tests that shell out to the ORIGINAL implementation must degrade
  gracefully when it is absent (early return), so sandboxed package builds
  (which only vendor the new crate) still pass.
