{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    # ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    claude-code
    python314Packages.jieba
    qtscrcpy
  ];
}
