{ pkgs, ... }:

{
  imports = [
    ../programs/Develop/code.nix
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

    sbctl

    libsForQt5.qt5ct
    kdePackages.qt6ct
  ];
}
