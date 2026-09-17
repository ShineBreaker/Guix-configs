# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 变通：锁定 bluebox 故意把 blue pin 在 guile-3.0（3.0.9，上游注释称
# 3.0.11 有 bug），而系统 profile 的 guix 模块已是 3.0.11 编译的字节码，
# 直接执行报 "incompatible bytecode version"。这里借系统 profile 的
# guile 3.0.11 直接以 -s 运行脚本主体（shebang 被当作注释跳过）；
# bluebox 升级 blue 的 guile 输入后可整体删除本函数。
function blue -d "blue（借系统 guile 3.0.11 运行，绕过字节码版本错配）"
    set -l guile /run/current-system/profile/bin/guile
    if test -x $guile
        $guile --no-auto-compile -e main -s $HOME/.guix-home/profile/bin/blue $argv
    else
        $HOME/.guix-home/profile/bin/blue $argv
    end
end
