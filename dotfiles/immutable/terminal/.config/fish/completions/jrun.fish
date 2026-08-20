# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_jrun_classes
    for f in bin/*.class
        test -f "$f"; or continue
        basename $f .class
    end
end

complete -c jrun -f -xa "(__fish_jrun_classes)"
