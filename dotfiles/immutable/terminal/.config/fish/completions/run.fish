# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __run_complete
    set -l tokens (commandline -opc 2>/dev/null)
    set -l args $tokens[2..-1]
    if test -f maak.scm
        complete -C "maak $args"
    else if test -f blueprint.scm
        complete -C "blue $args"
    else if test -f justfile; or test -f Justfile
        complete -C "just $args"
    end
end

complete -c run -f -a "(__run_complete)"
