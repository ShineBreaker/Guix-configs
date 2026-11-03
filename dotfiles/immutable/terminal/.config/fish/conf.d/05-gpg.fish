# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT
#
# git 调用 gpg 时 stdin 是管道，gpg 靠 GPG_TTY 找终端；SSH 登录后
# pinentry-curses 也依赖它把密码框画到当前 pty。
if status is-interactive; and tty >/dev/null 2>&1
    set -gx GPG_TTY (tty)
end
