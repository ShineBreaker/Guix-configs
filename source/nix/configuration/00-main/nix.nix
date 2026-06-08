{ pkgs, ... }:

{
  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = false;
  };

  nix = {
    package = pkgs.nix;
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "brokenshine" ];
      experimental-features = [ "nix-command" "flakes" ];
      builders-use-substitutes = true;
      keep-derivations = true;
      substituters = [
        "https://mirrors.ustc.edu.cn/nix-channels/store"
        "https://mirror.nju.edu.cn/nix-channels/store"
        "https://mirror.iscas.ac.cn/nix-channels/store"
        "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"

        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--delete-older-than 7d --keep 5";
    };
  };

}
