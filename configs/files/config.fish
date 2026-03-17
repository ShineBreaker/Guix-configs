# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: GPL-3.0

function __fastfetch_on_startup --on-event fish_prompt

    functions -e __fastfetch_on_startup
    $$bin/fastfetch$$
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | $$bin/lolcat$$

end

if status is-interactive

    fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
		fenv source /etc/environment

end

set -g fish_autosuggestion_enabled 1

# pnpm
mkdir -p $HOME/.local/share/pnpm
set -gx PNPM_HOME $HOME/.local/share/pnpm
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

$$bin/fzf$$ --fish | source

$$bin/zoxide$$ init fish | source
