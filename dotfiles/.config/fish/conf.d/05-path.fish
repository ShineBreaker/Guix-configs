## Nix
if status is-interactive

    fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
		fenv source /etc/environment

end

## PNPM
mkdir -p $HOME/.local/share/pnpm
set -gx PNPM_HOME $HOME/.local/share/pnpm
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end

## User
fish_add_path -g -a $HOME/.local/bin
