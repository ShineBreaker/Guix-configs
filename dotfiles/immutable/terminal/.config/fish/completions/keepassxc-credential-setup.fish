# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c keepassxc-credential-setup -f -n "__fish_use_subcommand" -a status -d "检查配置健康状态"
complete -c keepassxc-credential-setup -f -n "__fish_use_subcommand" -a init -d "初始化完整配置"
complete -c keepassxc-credential-setup -f -n "__fish_use_subcommand" -a update -d "更新过期的 callers 路径"
complete -c keepassxc-credential-setup -f -n "__fish_use_subcommand" -a callers -d "仅重新注册 callers"
