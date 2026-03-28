{ config, pkgs, ... }:

{
  imports = [
    ../home/programs/Develop/jujutsu.nix
    ../home/programs/Develop/pixi.nix
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

  home.packages = with pkgs; [
    android-tools
    qtscrcpy
    scrcpy

    sarasa-gothic
    bibata-cursors

    gamemode
    gamescope

    pmbootstrap

    libsForQt5.qt5ct
    kdePackages.qt6ct
  ];
}
