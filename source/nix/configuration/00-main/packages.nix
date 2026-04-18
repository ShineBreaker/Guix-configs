{ pkgs, ... }:

{
  imports = [
    ../programs/Develop/code.nix
  ];

  home.packages = with pkgs; [
    ## 编程工具
    beekeeper-studio
    bun
    pnpm
    postman

    ## Android 工具
    android-tools
    qtscrcpy
    scrcpy

    ## 工具
    broot
    gamemode
    gamescope
    gpu-screen-recorder-gtk
    pmbootstrap
    sunshine

    ## AI 工具
    claude-code
    codex
    crush
    opencode

    ## LSP
    bash-language-server
    kotlin-language-server
    nil
    package-version-server
    typescript-language-server
    vscode-langservers-extracted

    ## 版本管理
    jjui
    lazygit
    lazyjj
  ];
}
