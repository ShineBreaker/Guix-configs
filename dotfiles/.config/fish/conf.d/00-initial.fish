# SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

status is-interactive; and begin
    set -U fish_greeting

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

    fzf --fish | source
    starship init fish | source
end

function __fastfetch_on_startup --on-event fish_prompt
    functions -e __fastfetch_on_startup
    fastfetch
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | lolcat
end
