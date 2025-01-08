{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { 
    self, 
    nixpkgs, 
    nixpkgs-darwin, 
    nixpkgs-unstable, 
    nix-darwin, 
    ... 
    } @ inputs:
    let
      darwinConfiguration = hostname: username: 
        nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";

          specialArgs = {
            inherit self;
          };

          modules = [
            ./common/enable-flakes.nix
            ./common/darwin.nix
          ];
        };

      nixosConfiguration = hostname: username:
        nixpkgs.lib.nixosSystem {
          system = "x86_46-linux";

          modules = [
            ./common/enable-flakes.nix
            
            /etc/nixos/configuration.nix
          ];
        };
    in
    {
      darwinConfigurations = {
      };

      nixosConfigurations = {
      };
    };
}
