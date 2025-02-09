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
      nixosConfiguration = layout:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            /tmp/config/etc/nixos/configuration.nix

            disko.nixosModules.disko
            ./layouts/${layout}.nix

            ../common/ssh.nix
          ];
        };

    in
    {
      nixosConfigurations = {
        "single-ext4" = nixosConfiguration "single-ext4";
      };
    };
}