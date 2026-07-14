{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    broot
    gh
    python314Packages.jieba

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

    # AI Agent
    claude-code
    codex
    codex-acp

    (qq.override {
      commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
    })
  ];
}
