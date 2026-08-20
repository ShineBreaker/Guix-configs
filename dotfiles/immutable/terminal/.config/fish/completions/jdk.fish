# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c jdk -f -n "__fish_use_subcommand" -a set -d "切换 JDK 版本"
complete -c jdk -f -n "__fish_use_subcommand" -a current -d "显示当前版本"
complete -c jdk -f -n "__fish_seen_subcommand_from set" -r -f -a "8 11 17 21 25"
