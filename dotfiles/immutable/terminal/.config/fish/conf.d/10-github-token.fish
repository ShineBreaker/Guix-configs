# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

## GitHub API token：供调 REST API 的工具（Python 等）认证，
## 避免匿名 60 req/h 限流（403 rate limit exceeded）。
## 单一事实源是 gh CLI 登录凭据，运行时动态读取，不落盘新 secret。
set -l gh_tok (command gh auth token 2>/dev/null)
if test -n "$gh_tok"
    set -gx GITHUB_TOKEN $gh_tok
    set -gx GH_TOKEN $gh_tok
end
