# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0


# if we haven't sourced the login config, do it
status --is-login; and not set -q __fish_login_config_sourced
and begin

  set --prepend fish_function_path /run/current-system/profile/share/fish/functions
  fenv source /etc/profile
  fenv source $HOME/.profile
  set -e fish_function_path[1]

  set -g __fish_login_config_sourced 1

end

if status is-interactive
  atuin init fish | source
  direnv hook fish | source
  fzf --fish | source
  starship init fish | source
  zoxide init fish | source
end

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
abbr --add update 'sudo flatpak upgrade -y && flatpak upgrade -y && distrobox upgrade'
