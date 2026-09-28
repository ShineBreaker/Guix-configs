#!/usr/bin/env bash
# Regression probe: activity predicate used by cleanup/migration scripts.
# Verifies the `find -mtime` guard fires for a KNOWN-ACTIVE directory and
# stays quiet for an untouched one, under `set -euo pipefail`.
#
# Exit 0 = guard works. Exit 1 = guard is broken (inverted or always-false).
#
# The `find | grep -q` form is included as a negative control: under pipefail
# it reports active as INACTIVE. If that line ever starts printing "correct",
# the environment changed and this probe should be revisited.
#
# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
# SPDX-License-Identifier: MIT

set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# active_recent — the correct form (no pipe, no SIGPIPE)
active_recent() {
  [ -d "$1" ] && [ -n "$(find "$1" -type f -mtime -7 -print -quit 2>/dev/null)" ]
}

mkdir -p "$TMP/active" "$TMP/stale"
printf 'x\n' > "$TMP/active/state.db"
printf 'x\n' > "$TMP/stale/old.log"
# age the stale fixture past the 7-day window
touch -d '30 days ago' "$TMP/stale/old.log"

fail=0

if active_recent "$TMP/active"; then
  echo "ok   active dir detected"
else
  echo "FAIL active dir reported inactive"
  fail=1
fi

if active_recent "$TMP/stale"; then
  echo "FAIL stale dir reported active (mtime window broken)"
  fail=1
else
  echo "ok   stale dir ignored"
fi

# negative control: the broken form must report WRONG, proving this probe can
# actually tell the two implementations apart
if [ -d "$TMP/active" ] && find "$TMP/active" -type f -mtime -7 2>/dev/null | grep -q .; then
  echo "WARN pipefail+grep -q now reports correctly — environment changed, revisit probe"
else
  echo "ok   negative control reproduces the pipefail bug (as expected)"
fi

exit "$fail"
