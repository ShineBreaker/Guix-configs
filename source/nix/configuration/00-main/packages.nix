{ pkgs, ... }:

{
  imports = [ ../programs/00-main.nix ];

  home.packages = with pkgs; [
    ## Tools
    broot
    gh
    localsend
    python314Packages.jieba
    yaak

    ## Android
    android-tools
    pmbootstrap
    qtscrcpy
    scrcpy

    ## Gaming Tools
    gamescope
    mangojuice
    sunshine

    ## Environment management
    biome
    bun
    pnpm

    ## LSP
    bash-language-server
    kotlin-language-server
    nil
    package-version-server
    typescript-language-server
    vscode-langservers-extracted

    ## Chat
    discord
    feishu
    # wechat
    wemeet

    # AI Agent
    claude-code
    codex
    codex-acp

    ## Customized Packages
    (qq.override {
      commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
    })
  ];
}
