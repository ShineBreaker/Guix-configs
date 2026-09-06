# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

function run -d "按当前目录构建文件派发: maak.scm→maak, blueprint.scm→blue, justfile→just"
    if test -f maak.scm
        maak $argv
    else if test -f blueprint.scm
        blue $argv
    else if test -f justfile; or test -f Justfile
        just $argv
    else
        echo "run: 当前目录下未找到 maak.scm / blueprint.scm / justfile" >&2
        return 1
    end
end
