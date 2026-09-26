{ pkgs, ... }:

{
  imports = [
    ./code.nix
    ./llm-agents.nix
  ];

  home.packages =
    (with pkgs; [
      ## Tools
      beekeeper-studio
      localsend
      gh

      ## Editor
      android-studio
      apostrophe
      graphite

      ## Android
      android-tools
      pmbootstrap

      ## Gaming Tools
      gamescope
      mangojuice
      sunshine
      winetricks

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

      # Communication
      discord
      feishu-cli
      wechat
      wemeet

      (feishu.override {
        commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
      })

      (qq.override {
        commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
      })
    ])
    ++ (with pkgs.jetbrains; [
      idea
      pycharm
    ]);
}
