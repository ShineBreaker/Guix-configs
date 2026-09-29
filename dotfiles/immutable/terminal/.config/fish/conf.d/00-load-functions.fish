# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 提前 source functions/：fish 惰性 autoload，但 conf.d 之间会互调函数内部实现
# （如 05-java 的 __set_jdk），等 autoload 会错过初始化时机。
set -l functions_dir

if set -q XDG_CONFIG_HOME
    set functions_dir $XDG_CONFIG_HOME/fish/functions
else
    set functions_dir $HOME/.config/fish/functions
end

if test -d $functions_dir
    for func_file in $functions_dir/*.fish
        if test -f $func_file
            source $func_file
        end
    end
end
