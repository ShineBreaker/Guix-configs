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
  };

  outputs = { self, nixpkgs, ... }@inputs:

    (let
      system = "x86_64-linux";
      username = "brokenshine";

    in {
      homeConfigurations.Guix = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};

        modules = [
          ./configuration/00-main/home.nix
          ./configuration/programs/System/nix.nix
        ];

        extraSpecialArgs = { inherit inputs; };
      };

      # Aliases for home-manager compatibility
      homeConfigurations."${username}" = self.homeConfigurations.Guix;
      homeConfigurations."${username}@localhost" = self.homeConfigurations.Guix;
      homeConfigurations."${username}@$(hostname -s)" = self.homeConfigurations.Guix;
    });
}
