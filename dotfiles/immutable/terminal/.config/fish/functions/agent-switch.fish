function agent-switch --description "Switch agent config via stow"
    # ── Configuration ──────────────────────────────────────
    set -l stow_dir   ~/Documents/Stow
    set -l target     ~
    set -l state_file $stow_dir/.agent-current
    # ───────────────────────────────────────────────────────

    if test (count $argv) -eq 0
        echo "Usage: agent-switch <package>"
        echo ""
        echo "Available packages:"
        for pkg in (ls $stow_dir)
            # skip state file
            test "$pkg" = ".agent-current"; and continue
            echo "  $pkg"
        end
        # show current agent if set
        if test -f "$state_file"
            echo ""
            echo "Current: "(cat $state_file)
        end
        return 1
    end

    set -l pkg $argv[1]

    if not test -d "$stow_dir/$pkg"
        echo "Error: package '$pkg' not found in $stow_dir"
        return 1
    end

    # Read current agent
    set -l current ""
    if test -f "$state_file"
        set current (cat $state_file)
    end

    # Already active – nothing to do
    if test "$current" = "$pkg"
        echo "Already using: $pkg"
        return 0
    end

    # Unstow current agent (if any)
    if test -n "$current"
        echo "Removing current agent: $current"
        stow -d $stow_dir -t $target -D $current
    end

    # Build override flags for the new package
    set -l overrides
    if test -f "$stow_dir/$pkg/.claude/settings.json"
        set -a overrides --override .claude/settings.json
    end
    if test -f "$stow_dir/$pkg/.codex/config.toml"
        set -a overrides --override .codex/config.toml
    end
    if test -f "$stow_dir/$pkg/.codex/auth.json"
        set -a overrides --override .codex/auth.json
    end

    echo "Switching to: $pkg"
    stow -d $stow_dir -t $target --adopt $overrides $pkg

    # Persist new current agent
    echo $pkg > $state_file
end
