# SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

# status --is-login; and not set -q __fish_login_config_sourced
# and begin
#     fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
# end

function __fastfetch_on_startup --on-event fish_prompt
    functions -e __fastfetch_on_startup
    fastfetch
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | lolcat
end

fzf --fish | source
starship init fish | source
zoxide init fish | source
