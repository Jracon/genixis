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
      diskName = builtins.head (builtins.match "(/dev/[a-z0-9]+)" (builtins.readFile "/proc/partitions"));

      nixosConfiguration = layout:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = {
            inherit diskName;
          };

          modules = [
            /tmp/config/etc/nixos/configuration.nix
            disko.nixosModules.disko
            ./layouts/${layout}.nix
          ];
        };

    in
    {
      nixosConfigurations = {
        "single-ext4" = nixosConfiguration "single-ext4";
      };
    };
}