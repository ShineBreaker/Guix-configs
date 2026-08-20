# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function __fish_jbuild_classes
    for f in src/*.java
        test -f "$f"; or continue
        basename $f .java
    end
end

complete -c jbuild -f -xa "(__fish_jbuild_classes)"
