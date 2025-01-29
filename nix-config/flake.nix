{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    home-manager, 
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

      homeManagerConfiguration = system: hostname: username:  
        home-manager.lib.homeManagerConfiguration {
        };

      nixosConfiguration = system: hostname: username: isVirtualizer:
        nixpkgs.lib.nixosSystem {
          modules = [
            /etc/nixos/configuration.nix
            ./common/enable-flakes.nix
            ./common/ssh.nix
          ] ++ virtualizationModules.${isVirtualizer};
        };

      virtualizationModules = {
        manager = [
          ./common/incus.nix
        ];

        null = [ ];
      };
    in
    {
      darwinConfigurations = {
        "m1-mbp" = darwinConfiguration "m1-mbp" "jademeskill";
      };

      homeConfigurations = {
      };

      nixosConfigurations = {
        "test" = nixosConfiguration "aarch64" "test_hostname" "test_user" "null";
        "manager" = nixosConfiguration "x86_64-linux" "nixos-incus" "root" "manager";
      };
    };
}
