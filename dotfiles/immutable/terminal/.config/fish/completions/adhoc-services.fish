# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c adhoc-services -x -a reload -d "扫描目录，加载并启动全部服务"
complete -c adhoc-services -x -a list -d "列出目录中的服务名"
complete -c adhoc-services -x -a enable -d "从 stdin 读定义写入并重载"
complete -c adhoc-services -x -a disable -d "停止、注销并移走定义"
