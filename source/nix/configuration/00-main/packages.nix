{ pkgs, ... }:

{
  imports = [ ../programs/Develop/code.nix ];

  home.packages = with pkgs; [
    android-tools
    broot
    bun
    claude-code
    package-version-server
    pnpm
    qtscrcpy
    scrcpy
    tpm2-abrmd
    tpm2-pkcs11

    gpu-screen-recorder-gtk
    sunshine

    git-credential-keepassxc
    nerd-fonts.iosevka

    sarasa-gothic
    bibata-cursors

    gamemode
    gamescope

    pmbootstrap

    beekeeper-studio
    postman

    codex
    crush
    opencode

    bash-language-server
    kotlin-language-server
    nil
    typescript-language-server
    vscode-langservers-extracted
  ];
}
