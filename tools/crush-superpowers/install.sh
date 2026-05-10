#!/usr/bin/env bash
# Install Superpowers skills for Crush CLI
# Usage: bash install.sh [SKILLS_DIR]
#
# Crush requires the `name` field in SKILL.md frontmatter to exactly match
# the directory name. We keep original skill names (no prefix) and check
# for conflicts before installing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUPERPATH="$SCRIPT_DIR/main"
SKILLS_DIR="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/agents/skills}"

if [[ ! -d "$SUPERPATH/skills" ]]; then
    echo "Error: '$SUPERPATH/skills' not found."
    echo "Ensure 'main/' contains the superpowers repo."
    exit 1
fi

mkdir -p "$SKILLS_DIR"
echo "Installing Superpowers skills into: $SKILLS_DIR"
echo "Source: $SUPERPATH"
echo ""

# Check for naming conflicts
conflicts=0
for skill_dir in "$SUPERPATH/skills"/*; do
    [[ -d "$skill_dir" ]] || continue
    name=$(basename "$skill_dir")
    if [[ -d "$SKILLS_DIR/$name" ]]; then
        echo "  ✗ CONFLICT: '$name' already exists in $SKILLS_DIR"
        conflicts=$((conflicts + 1))
    fi
done

if [[ $conflicts -gt 0 ]]; then
    echo ""
    echo "Error: $conflicts conflict(s) found. Resolve them before installing."
    exit 1
fi

# Copy each skill with original name
installed=0
for skill_dir in "$SUPERPATH/skills"/*; do
    [[ -d "$skill_dir" ]] || continue
    name=$(basename "$skill_dir")
    target="$SKILLS_DIR/$name"

    cp -r "$skill_dir" "$target"
    echo "  ✓ $name"
    installed=$((installed + 1))
done

echo ""
echo "=== $installed skills installed ==="
echo ""
echo "Restart Crush to activate. Verify by sending:"
echo '  "Let'\''s make a react todo list"'
echo ""
echo "The agent should trigger brainstorming BEFORE writing any code."
echo ""
echo "To update: re-run this script (copies are overwritten)."
echo "To uninstall: rm -rf $SKILLS_DIR/<skill-name>"
