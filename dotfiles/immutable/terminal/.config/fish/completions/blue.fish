# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_blue_complete
    set -l line (commandline -cp 2>/dev/null)
    if test -z "$line"
        set line (commandline -c 2>/dev/null)
    end
    if test -z "$line"
        set line "blue "
    else if not string match -q "blue*" -- "$line"
        set line "blue $line"
    end
    set -l raw (blue ,autocomplete bash "$line" 2>/dev/null | string trim)
    if test -z "$raw"
        return
    end
    for token in (string split " " -- $raw)
        set -l t (string trim -- "$token")
        test -n "$t"; and echo $t
    end
end

complete -c blue -f -a "(__fish_blue_complete)"
