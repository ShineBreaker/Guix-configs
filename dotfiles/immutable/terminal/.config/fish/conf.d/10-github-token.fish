# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 供 REST API 工具认证避免匿名限流；单一事实源是 gh 凭据，动态读取不落盘。
# type -q 守卫不可省：gh 缺失时 command gh 走 fish 的 command-not-found 路径，
# 其诊断输出走 shell 自身 stderr、绕过硬重定向 2>/dev/null，每次启动都刷屏。
if type -q gh
    set -l gh_tok (command gh auth token 2>/dev/null)
    if test -n "$gh_tok"
        set -gx GITHUB_TOKEN $gh_tok
        set -gx GH_TOKEN $gh_tok
    end
end
