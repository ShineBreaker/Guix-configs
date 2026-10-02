# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# ── quicktui-server 子命令补全 ──────────────────────────────────────
# 上游不提供 fish 补全；子命令清单摘自 `quicktui-server --help`。
# 服务日常由 home shepherd 管理（herd restart quicktui），勿手动 serve。

complete -c quicktui-server -f

complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a serve -d 前台起服务
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a pairing -d 设备配对与身份管理
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a upgrade -d "检查 / 安装新版本"
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a service -d "注册系统服务（本机用 shepherd）"
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a doctor -d 自检外部依赖
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a hooks -d "AB2 agent hooks 管理"
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a config -d "查看 / 修改运行时配置"
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a auth -d "Relay 登录与绑定"
complete -c quicktui-server -n "not __fish_seen_subcommand_from serve pairing upgrade service doctor hooks config auth version help" -a version -d 打印版本

complete -c quicktui-server -n "__fish_seen_subcommand_from pairing" -a "welcome qrcode relay addresses devices identity"
complete -c quicktui-server -n "__fish_seen_subcommand_from upgrade" -a "check install"
complete -c quicktui-server -n "__fish_seen_subcommand_from service" -a "install uninstall restart"
complete -c quicktui-server -n "__fish_seen_subcommand_from hooks" -a "install uninstall status"
complete -c quicktui-server -n "__fish_seen_subcommand_from config" -a "show set relay"
complete -c quicktui-server -n "__fish_seen_subcommand_from auth" -a "login bind unbind usage logout"

complete -c quicktui-server -n "__fish_seen_subcommand_from serve" -l config -d 配置文件路径 -r
complete -c quicktui-server -n "__fish_seen_subcommand_from serve" -l debug-addr -d 监听地址覆盖 -r
complete -c quicktui-server -n "__fish_seen_subcommand_from serve" -l term -d "tmux TERM" -r
complete -c quicktui-server -n "__fish_seen_subcommand_from serve" -l lang -d "tmux LANG" -r
complete -c quicktui-server -n "__fish_seen_subcommand_from serve" -l tmux-socket -d "tmux socket 路径" -r
