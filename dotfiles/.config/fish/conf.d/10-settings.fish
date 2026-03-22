# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

set -g fish_autosuggestion_enabled 1

alias cat "bat"
alias cd "z"
alias cp "cp -i"
alias find "fd"
alias grep "rg"
alias htop "btop"
alias ll "ls -la"
alias rm "rm -i"

abbr --add commit 'git commit --all -S'
abbr --add enter distrobox enter
abbr --add push git push
abbr --add reboot loginctl reboot
abbr --add shutdown loginctl poweroff
abbr --add update 'sudo flatpak upgrade -y && flatpak upgrade -y && distrobox upgrade --all'
