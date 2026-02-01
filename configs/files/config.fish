# SPDX-FileCopyrightText: 2026 Copyright (C) 2024-2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

if status is-interactive
    set --prepend fish_function_path /run/current-system/profile/share/fish/functions
    fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
end

function __fastfetch_on_startup --on-event fish_prompt
    functions -e __fastfetch_on_startup
    $$bin/fastfetch$$
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | $$bin/lolcat$$
end

$$bin/fzf$$ --fish | source

$$bin/starship$$ init fish | source

$$bin/zoxide$$ init fish | source
