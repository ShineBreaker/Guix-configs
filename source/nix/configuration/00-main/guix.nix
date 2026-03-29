{ config, pkgs, ... }:

{
  imports = [
    ../programs/System/nix.nix
  ];

  targets.genericLinux.enable = true;

  home.username = "brokenshine";
  home.homeDirectory = "/home/brokenshine";
  home.stateVersion = "25.11";

  home.sessionVariables = {
    NIXOS_OZONE_WL = 1;
  };

  programs.home-manager.enable = true;

  xdg.enable = true;
}
