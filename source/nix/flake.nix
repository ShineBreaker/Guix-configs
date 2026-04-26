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

    charmbracelet-nur = {
      url = "github:charmbracelet/nur";
      inputs.nixpkgs.follows = "nixpkgs";
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
            {
              nixpkgs.overlays = [ inputs.nur.overlays.default ];
            }
            ./configuration/00-main/home.nix
            ./configuration/programs/System/nix.nix


            inputs.nur.modules.homeManager.default
            inputs.charmbracelet-nur.homeModules.crush
          ];

          extraSpecialArgs = { inherit inputs; };
        };
    });
}
