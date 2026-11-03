# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

set -g fish_autosuggestion_enabled 1

alias cat bat
alias catr cat
alias cd z
alias ee 'emacsclient --tty --alternate-editor=""'
alias clone "git clone"
alias cp "cp -i"
alias du dust
alias find fd
alias grep rg
alias htop btop
alias ll "ls -la"
alias ls eza
alias rm "rm -i"

abbr --add status	'git status -sb'
abbr --add add	'git add'
abbr --add commit	'git commit -S'
abbr --add commitall	'git commit --all -S'
abbr --add push	'git push'
abbr --add pull	'git pull'
abbr --add fetch	'git fetch'
abbr --add diff	'git diff'
abbr --add log	'git log'
abbr --add clone	'git clone'

abbr --add cl 'claude --dangerously-skip-permissions'
abbr --add enter distrobox enter
abbr --add push git push
abbr --add reboot loginctl reboot
abbr --add shutdown loginctl poweroff
