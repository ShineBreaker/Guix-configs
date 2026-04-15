{ pkgs, ... }:

{
  imports = [ ../programs/Develop/code.nix ];

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

    beekeeper-studio
    postman

    crush
    opencode

    bash-language-server
    kotlin-language-server
    nil
    typescript-language-server
    vscode-langservers-extracted
  ];
}
