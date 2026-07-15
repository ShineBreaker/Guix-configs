{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    apostrophe
    broot
    localsend
    gh
    python314Packages.jieba

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

      noto-fonts = sarasa-gothic;
      noto-fonts-lgc-plus = sarasa-gothic;
      noto-fonts-cjk-sans = sarasa-gothic;
    })

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
    claude-agent-acp
    codex
    codex-acp

    # Communication
    discord
    feishu
    feishu-cli
    wechat
    wemeet

    (qq.override {
      commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
    })
  ];
}
