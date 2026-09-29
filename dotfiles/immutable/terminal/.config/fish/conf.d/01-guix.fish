# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 登录 shell 里经 fenv 继承 ~/.profile（guix profile 环境）；守卫变量防重复 source。
# 各 conf.d 语义见 docs/scripts/fish-conf-d.md
status --is-login; and not set -q __fish_login_config_sourced
and begin

    fenv source $HOME/.profile
    set -e fish_function_path[1]

    set -g __fish_login_config_sourced 1

end
