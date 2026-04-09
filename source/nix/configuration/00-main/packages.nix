{ pkgs, ... }:

{
  imports = [
    ../programs/Develop/code.nix
  ];

  home.packages = with pkgs; [
    android-tools
    qtscrcpy
    scrcpy

    gpu-screen-recorder-gtk
    sunshine

    sarasa-gothic
    bibata-cursors

    gamemode
    gamescope

    pmbootstrap
    sbctl

    beekeeper-studio
    postman

    opencode
    opencode-desktop

    libsForQt5.qt5ct
    kdePackages.qt6ct
  ];
}
