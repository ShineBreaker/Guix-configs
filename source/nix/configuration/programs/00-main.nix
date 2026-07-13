{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    # ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    claude-code
    claude-agent-acp
    python314Packages.jieba
    qtscrcpy

    (qq.override {
      commandLineArgs = "--ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime --wayland-text-input-version=3";
    })
  ];
}
