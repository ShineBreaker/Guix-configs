if status is-interactive
    fenv . $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh
end

function __fastfetch_on_startup --on-event fish_prompt
    functions -e __fastfetch_on_startup
    fastfetch
    echo \n日々私たちが過ごしている日常は、実は、奇跡の連続なのかもしれない。\n | lolcat
end
