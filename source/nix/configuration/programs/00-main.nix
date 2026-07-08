{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    # ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    python314Packages.jieba
    qtscrcpy
  ];
}
