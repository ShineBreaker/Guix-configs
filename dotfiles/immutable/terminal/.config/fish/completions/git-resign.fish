# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

complete -c git-resign -f -d "重签名 <base-ref>..HEAD 的所有提交"
complete -c git-resign -f -a "HEAD~1 HEAD~2 HEAD~3 HEAD~5" -d "基线引用，也接受 43d43e4~1 这类短哈希"
