# Shell quirks confirmed empirically — mirror these, do not rationalize them

Each rule was verified against real GNU grep/sed/bash before porting.
Re-verify if the toolchain changes; do not trust memory.

- Top-level `return` in an executed (non-sourced) script prints a
  locale-specific error and FALLS THROUGH — it does not exit and the exit
  code comes from whatever runs last. Mirror the fall-through bytes, not an
  early return; the error line itself is the one accepted stderr divergence.
- A sed address-range opener never self-closes: in `/A/,/B/`, the line that
  opens the range is processed and stays open; only a LATER line matching B
  closes it (after processing). Checking B on the opener skips the body.
- `1i a\nb\n` inserts THREE lines including a trailing blank one — the
  trailing `\n` is data, not terminator. A `1i` without trailing `\n`
  inserts no blank line. Count them exactly per call site.
- `/A/,/B/a text` appends after EVERY line in the range, endpoints included —
  not just after B. A range-scoped append is not a global append; port the
  range tracking, not the action alone.
- `s` without `g` replaces the FIRST match per line only; `a`/`i` act on every
  matching line, not just the first. Never deduplicate sed actions.
- `grep -q` patterns without `$` match trailing garbage; `\s*` also matches
  zero whitespace, so `return\s*config` matches `returnconfig` and
  `return config2`. Port the regex, not the intent.
- `echo -e "\nLINE\n"` emits leading AND trailing blank lines plus echo's own
  newline; plain `echo x >>` appends with no newline normalization — a file
  without trailing newline gets the text glued to its last line. Keep the
  concatenation exact.
- `ln -sf` replaces the link; `cp --remove-destination` unlinks first, so a
  symlink destination becomes a regular file (writing through it instead
  changes the TARGET — different outcome, detectable by diff).
