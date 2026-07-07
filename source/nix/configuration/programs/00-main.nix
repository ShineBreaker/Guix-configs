{ pkgs, ... }:

{
  imports = [
    ./hermes.nix
    ./zed.nix
  ];

  home.packages = with pkgs; [
    ## Tools
    python314Packages.jieba

    ## Android
    android-tools
    qtscrcpy

    ## LSP
    bash-language-server
    kotlin-language-server
    nil
    package-version-server
    typescript-language-server
  ];

}
