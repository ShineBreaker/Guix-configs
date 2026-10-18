# SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
#
# SPDX-License-Identifier: MIT

## Nix（hm-session-vars 由 home-manager 生成，fenv 继承）
# fenv . $XDG_STATE_HOME/nix/profile/etc/profile.d/hm-session-vars.sh
# fish_add_path -g -a $XDG_STATE_HOME/nix/profile/bin

## PNPM：不设 PNPM_HOME，global 安装已废弃（anchors 冻结 pnpm/npm global）；
## store 位置由 XDG_DATA_HOME 推导，仍是 ~/.local/share/pnpm/store，不受影响

## User
fish_add_path -g -a $HOME/.local/bin
