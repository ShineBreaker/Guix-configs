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
    codex
    codex-acp
    python314Packages.jieba
    qtscrcpy
  ];
}
