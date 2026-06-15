{ ... }:

{
  imports = [ ./packages.nix ../programs/nix.nix ];

  targets.genericLinux.enable = true;

  home = {
    username = "brokenshine";
    homeDirectory = "/home/brokenshine";
    stateVersion = "25.11";

    extraOutputsToInstall = [ "doc" ];
  };

  home.sessionVariables = {
    NIXOS_OZONE_WL = 1;
    CHROMIUM_FLAGS =
      "--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=wayland --enable-wayland-ime --wayland-text-input-version=3";
  };

  programs.home-manager.enable = true;

  xdg.enable = true;
}
