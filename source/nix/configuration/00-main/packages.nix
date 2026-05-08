{ pkgs, ... }:

{
  imports = [ ../programs/00-main.nix ];

  home.packages = with pkgs; [
    ## 编程工具
    beekeeper-studio
    postman

    ## Android
    android-tools
    qtscrcpy
    scrcpy

    ## 工具
    gamescope
    pmbootstrap
    sunshine

    ## 文本编辑
    apostrophe
    obsidian

    ## AI 工具
    tabby-agent

    ## LSP
    bash-language-server
    kotlin-language-server
    nil
    package-version-server
    typescript-language-server
    vscode-langservers-extracted
  ];
}
