# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

# 供 REST API 工具认证避免匿名限流；单一事实源是 gh 凭据，动态读取不落盘。
set -l gh_tok (command gh auth token 2>/dev/null)
if test -n "$gh_tok"
    set -gx GITHUB_TOKEN $gh_tok
    set -gx GH_TOKEN $gh_tok
end
