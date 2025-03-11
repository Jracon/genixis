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
      generateConfigModules = config: 
        let
          modules = builtins.concatMap (key: 
            let
              values = if config ? ${key} then 
                (if builtins.isList config.${key} then config.${key} else [ config.${key} ]) 
              else 
                [];
            in 
              builtins.concatMap (value: 
                let 
                  path = ./${key}/${toString value};
                  filePath = path + ".nix";
                in 
                  if builtins.pathExists filePath then 
                    [ filePath ]
                  else if builtins.pathExists path && builtins.isPath path then 
                    let 
                      nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) 
                        (builtins.attrNames (builtins.readDir path)); 
                    in 
                      builtins.map (name: path + "/${name}") nixFiles
                  else 
                    []
              ) values 
          ) (builtins.attrNames config);

          diskoModule = if config ? "disk-layouts" then [ disko.nixosModules.disko ] else [];
        in
          modules ++ diskoModule;

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
      
      diskoConfiguration = layout: devices: 
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit devices;
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

      nixosConfiguration = hostname: config: devices: 
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = {
            inherit devices;
          };

          modules = [
            /etc/nixos/configuration.nix

            ./common/enable-flakes.nix
            ./common/ssh.nix
          ] ++ generateConfigModules config;
        };
    in
      {
        darwinConfigurations = {
          "m1-mbp" = darwinConfiguration "m1-mbp" "jademeskill";
        };

        homeConfigurations = {
        };

        nixosConfigurations = {
          "disko@single-ext4" = diskoConfiguration "single-ext4" {disks = [ "/dev/sda" ];};
          
          "incus" = nixosConfiguration "incus" { disk-layouts = "single-ext4"; roles = [ "incus" ]; } { disks = [ "/dev/sda" ]; interfaces = [ "eno1" ]; };
          "docker" = nixosConfiguration "docker" { roles = [ "docker" ]; containers = [ "media-servers" ]; } { };
          "podman" = nixosConfiguration "podman" { roles = [ "podman" ]; containers = [ "media-servers" ]; } { };
        };
      };
}
