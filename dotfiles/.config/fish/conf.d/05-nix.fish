if status is-interactive

    fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
		fenv source /etc/environment

end
