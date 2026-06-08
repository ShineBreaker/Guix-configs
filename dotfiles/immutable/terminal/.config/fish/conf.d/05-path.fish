# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

## Nix
fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
fish_add_path -g -a $HOME/.nix-profile/bin

## PNPM
mkdir -p $HOME/.local/share/pnpm
set -gx PNPM_HOME $HOME/.local/share/pnpm
if not string match -q -- $PNPM_HOME $PATH
    set -gx PATH "$PNPM_HOME" $PATH
end

## User
fish_add_path -g -a $HOME/.local/bin
