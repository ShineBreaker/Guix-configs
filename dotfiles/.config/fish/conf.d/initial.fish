status is-interactive; and begin

    # Abbreviations
    abbr --add -- cat bat
    abbr --add -- cd z
    abbr --add -- commit 'git commit --all'
    abbr --add -- enter 'distrobox enter'
    abbr --add -- push 'git push'
    abbr --add -- reboot 'sudo reboot'
    abbr --add -- rebuild 'sudo guix system reconfigure ./config.scm && guix home reconfigure ./home-config.scm'
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

    enable_transience
end

fastfetch
