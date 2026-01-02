status is-interactive; and begin

    # Abbreviations
    abbr --add -- cd z
    abbr --add -- commit 'git commit --all'
    abbr --add -- enter 'toolbox enter'
    abbr --add -- ls eza
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

    # Interactive shell initialisation
    fzf --fish | source

    fastfetch
    set --global fish_greeting 日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。

    if test "$TERM" != dumb
        starship init fish | source
        direnv hook fish | source
        zoxide init fish | source
        enable_transience
    end

end
