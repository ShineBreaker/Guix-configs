{ pkgs, ... }:

{
  imports = [ ../programs/00-main.nix ];

  home.packages = with pkgs; [
    ## Tools
    broot
    gh
    localsend
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
    wechat
    wemeet

    ## Customized Packages
    (libreoffice.overrideAttrs {
      variant = "fresh";
      withHelp = false;
      kdeIntegration = false;
      withJava = false;

      langs = [
        "en-GB"
        "en-US"
        "zh-CN"
      ];
    })
    (qq.override {
      commandLineArgs = "--enable-wayland-ime --wayland-text-input-version=3";
    })
  ];
}
