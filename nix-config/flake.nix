{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";

    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { 
    self, 
    disko, 
    home-manager, 
    nixpkgs, 
    nixpkgs-darwin, 
    nixpkgs-stable, 
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
      
      diskoConfiguration = layout: disks: 
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit disks;
          };

          modules = [
            disko.nixosModules.disko
            ./disk-layouts/${layout}.nix
            /mnt/etc/nixos/configuration.nix
          ];
        };

      homeManagerConfiguration = username:  
        home-manager.lib.homeManagerConfiguration {
        };

      nixosConfiguration = hostname: role: containers: layout: disks: interfaces:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = {
            inherit disks;
            inherit interfaces;
          };

          modules = [
            /etc/nixos/configuration.nix

            ./common/enable-flakes.nix
            ./common/ssh.nix
          ] ++ (if layout != null then [ disko.nixosModules.disko ./disk-layouts/${layout}.nix ] else [ ])
            ++ (if role != null then [ ./roles/${role}.nix ] else [ ])
            ++ (if containers != null then map (container: ./containers/${container}.nix) containers else [ ]);
        };
    in
    {
      darwinConfigurations = {
        "m1-mbp" = darwinConfiguration "m1-mbp" "jademeskill";
      };

      homeConfigurations = {
      };

      nixosConfigurations = {
        "test" = nixosConfiguration "test_hostname" null null "single-ext4" [ "/dev/sda" ] null;
        "disko@test" = diskoConfiguration "single-ext4" [ "/dev/sda" ];
        
        "incus" = nixosConfiguration "incus" "incus" null "single-ext4" [ "/dev/sda" ] [ "eno1" ];
        "docker" = nixosConfiguration "docker" "docker" [ "jellyfin" ] null null null;
      };
    };
}
