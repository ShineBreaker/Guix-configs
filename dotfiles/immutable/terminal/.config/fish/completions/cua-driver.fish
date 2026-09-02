# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c cua-driver -f

set -l subcommands mcp list-tools describe call serve stop revoke status config telemetry recording update check-update doctor diagnose permissions autostart skills manifest channel cursor-theme sessions history

complete -c cua-driver -n '__fish_use_subcommand' -a "$subcommands"
complete -c cua-driver -n '__fish_use_subcommand' -l help -d '显示帮助'
complete -c cua-driver -n '__fish_use_subcommand' -l json -d '结构化 JSON 输出'
complete -c cua-driver -n '__fish_seen_subcommand_from update' -l apply -d '下载并安装最新版'
complete -c cua-driver -n '__fish_seen_subcommand_from skills' -a 'install update uninstall status path'
complete -c cua-driver -n '__fish_seen_subcommand_from channel' -a 'status set'
