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
    qq
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
      # niri 26.04 的 zwp_text_input_v3 实现有 bug（niri#3067），不发 done 事件，
      # 导致 Electron 应用（QQ）走 wayland text-input 协议时 IME 失效。
      # 临时切到 X11 ozone 后端，让 QQ 跑在 XWayland 里、用 XIM 协议跟 fcitx5 通信。
      # 等 niri 修 bug 后再切回 --enable-wayland-ime。
      commandLineArgs = "--ozone-platform=x11";
    })
  ];
}
