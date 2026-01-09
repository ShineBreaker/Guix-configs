status is-interactive; and begin

    # Abbreviations
    abbr --add -- cd z
    abbr --add -- commit 'git commit --all'
    abbr --add -- enter 'distrobox enter'
    abbr --add -- rebuildh 'guix home reconfigure ./home-config.scm'
    abbr --add -- push 'git push'
    abbr --add -- reboot 'sudo reboot'
    abbr --add -- rebuild 'sudo guix system reconfigure ./config.scm'
    abbr --add -- shutdown 'sudo poweroff'
    abbr --add -- update 'sudo ll-cli upgrade && sudo flatpak upgrade'
    abbr --add -- upgrade 'guix pull'

    # Aliases
    alias la 'eza -a'
    alias ll 'eza -l'
    alias lla 'eza -la'
    alias ls eza
    alias lt 'eza --tree'

    fzf --fish | source
    starship init fish | source
    direnv hook fish | source
    zoxide init fish | source

    enable_transience
end

fastfetch