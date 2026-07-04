#!/usr/bin/env bash
# Probe script: diagnose Hermes memory routing health.
#
# Run this when you suspect the agent is writing only to MEMORY.md while
# `memory.provider: holographic` (or other external provider) is configured.
#
# Diagnosis rule of thumb:
#   MEMORY.md > 1 KB  AND  facts < 5 rows  →  routing is broken
#
# Exit codes:
#   0 — both channels look healthy (or no provider configured)
#   1 — probe error (missing db, missing config, etc.)
#   2 — routing broken (MEMORY.md is the only thing growing)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.local/share/hermes}"
CONFIG="$HERMES_HOME/config.yaml"
MEM_DIR="$HERMES_HOME/memories"
DB="$HERMES_HOME/memory_store.db"

echo "=== provider (config.yaml) ==="
if [[ -f "$CONFIG" ]]; then
  awk '/^memory:/,/^[a-z]/' "$CONFIG" | grep -E 'provider|memory_enabled|user_profile_enabled' || echo "(no memory block)"
else
  echo "(no config.yaml at $CONFIG)"
fi

echo
echo "=== MEMORY.md / USER.md ==="
for f in MEMORY.md USER.md; do
  if [[ -f "$MEM_DIR/$f" ]]; then
    printf '  %s: %s bytes, %s lines\n' "$f" "$(wc -c < "$MEM_DIR/$f")" "$(wc -l < "$MEM_DIR/$f")"
  else
    printf '  %s: missing\n' "$f"
  fi
done

echo
echo "=== facts (memory_store.db) ==="
if [[ -f "$DB" ]]; then
  TOTAL=$(sqlite3 "$DB" 'SELECT COUNT(*) FROM facts;' 2>/dev/null || echo "?")
  echo "  total facts: $TOTAL"
  if [[ "$TOTAL" != "0" && "$TOTAL" != "?" ]]; then
    echo "  by category:"
    sqlite3 -separator '  ' "$DB" \
      'SELECT "    " || category, COUNT(*) FROM facts GROUP BY category;' \
      2>/dev/null || true
  fi
else
  echo "  (no $DB)"
fi

echo
echo "=== drift artifacts ==="
shopt -s nullglob
BKS=("$MEM_DIR"/*.bak.*)
LKS=("$MEM_DIR"/*.lock)
shopt -u nullglob
if [[ ${#BKS[@]} -gt 0 || ${#LKS[@]} -gt 0 ]]; then
  printf '  %s\n' "${BKS[@]}" "${LKS[@]}"
else
  echo "  (none)"
fi

# Final diagnosis
echo
echo "=== verdict ==="
if [[ ! -f "$DB" ]]; then
  echo "  no external provider DB found — nothing to check"
  exit 0
fi

MEM_BYTES=0
if [[ -f "$MEM_DIR/MEMORY.md" ]]; then
  MEM_BYTES=$(wc -c < "$MEM_DIR/MEMORY.md")
fi
FACT_COUNT=$(sqlite3 "$DB" 'SELECT COUNT(*) FROM facts;' 2>/dev/null || echo "0")

if (( MEM_BYTES > 1024 && FACT_COUNT < 5 )); then
  echo "  ⚠  routing broken: MEMORY.md is ${MEM_BYTES}B but only ${FACT_COUNT} facts stored"
  echo "     → see hermes-memory-routing skill, Option A (SOUL.md rule)"
  exit 2
else
  echo "  ✓ routing looks healthy"
  exit 0
fi