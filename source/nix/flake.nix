{
  description = "self-using configuration.";

  inputs = {
    flake-compat.url = "github:NixOS/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs = { nixpkgs.follows = "nixpkgs"; };
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
      };
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:

    (let
      system = "x86_64-linux";
      username = "brokenshine";

    in {
      homeConfigurations.Guix =
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};

          modules = [
            configuration/00-main/guix.nix
            configuration/00-main/packages.nix
          ];

          extraSpecialArgs = { inherit inputs; };
        };
    });
}
