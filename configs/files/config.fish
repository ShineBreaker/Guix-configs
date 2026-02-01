# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# if we haven't sourced the login config, do it
status --is-login; and not set -q __fish_login_config_sourced
and begin

  set --prepend fish_function_path /gnu/store/l8qrim1xchsv7kl4j0vs0qm588fc4apn-fish-foreign-env-0.20230823/share/fish/functions
  fenv source /etc/profile
  fenv source $HOME/.profile

end

function __fastfetch_on_startup --on-event fish_prompt
    functions -e __fastfetch_on_startup
    /gnu/store/1mr7qxygpvm3nf7apkg63k31r4abz6s7-fastfetch-2.57.0/bin/fastfetch
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | /gnu/store/f4nidj2rlb4yns9l0gdnh9f5426axs6d-lolcat-1.5/bin/lolcat
end

fzf --fish | source

starship init fish | source

zoxide init fish | source

direnv hook fish | source

atuin init fish | source

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
