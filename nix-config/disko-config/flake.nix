{
  description = "";

  inputs = {
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { 
    self, 
    disko, 
    nixpkgs,
    ...
    } @ inputs: 
    let
      layoutModules = {
        single-ext4 = [
          ./layouts/single-ext4.nix
        ];
      };

      nixosConfiguration = layout:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            /tmp/config/configuration.nix
            disko.nixosModules.disko
          ] ++ layoutModules.${layout};
        };
    in 
    {
      nixosConfigurations = {
        "single-ext4" = nixosConfiguration "single-ext4";
      };
    };
}
