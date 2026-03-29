{ config, pkgs, ... }:

{
  imports = [
    ../programs/Develop/code.nix
    ../programs/Utility/ai-tools.nix
  ];

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
