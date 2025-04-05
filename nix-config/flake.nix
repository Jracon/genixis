{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    agenix.url = "github:ryantm/agenix";

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
    agenix,
    disko,
    home-manager,
    nixpkgs,
    nixpkgs-darwin,
    nixpkgs-stable,
    nix-darwin,
    ...
  } @ inputs:

  let
    generateConfigModules = config: local:
      let
        modules = builtins.concatMap (
          key:
          let
            values = if config ? ${key} 
                     then (
                       if builtins.isList config.${key} 
                       then config.${key} 
                       else [ config.${key} ]
                     )
                     else [ ];
          in
            builtins.concatMap (
              value:
              let
                path = ./${key}/${toString value};
                filePath = path + ".nix";
              in
                if builtins.pathExists filePath 
                then [ filePath ]
                else if builtins.pathExists path && builtins.isPath path 
                then let
                  nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
                    builtins.attrNames (builtins.readDir path)
                  );
                in
                  builtins.map (name: path + "/${name}") nixFiles
                else [ ]
            ) values
        ) (builtins.attrNames config);

        diskoModules = if local ? "disk-layout"
                      then [ disko.nixosModules.disko ./disk-layouts/${local.disk-layout} ] 
                      else [ ];
      in
        modules ++ diskoModules;

    darwinConfiguration = hostname: username:
      nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";

        specialArgs = {
          inherit self;
        };

        modules = [
          ./common/agenix.nix
          ./common/enable-flakes.nix
          ./common/darwin.nix

          agenix.nixosModules.default
          {
            environment.systemPackages = [ agenix.packages."aarch64-darwin".default ];
          }
        ];
      };

    diskoConfiguration = layout: 
      let 
        local = import /tmp/etc/nixos/local.nix;
      in
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit local; 
          };

          modules = [
            /tmp/etc/nixos/configuration.nix

            disko.nixosModules.disko
            ./disk-layouts/${layout}.nix
          ];
        };

    homeManagerConfiguration = username:
      home-manager.lib.homeManagerConfiguration {
      };

    nixosConfiguration = config: 
      let 
        local = import /etc/nixos/local.nix;
      in
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          specialArgs = {
            inherit local;
          };

          modules = [
            /etc/nixos/configuration.nix

            ./common/agenix.nix
            ./common/enable-flakes.nix
            ./common/minimal.nix
            ./common/ssh.nix

            agenix.nixosModules.default
            {
              environment.systemPackages = [ agenix.packages."x86_64-linux".default ];
            }
          ] ++ generateConfigModules config local;
        };
  in
    {
      darwinConfigurations = {
        "m1-mbp" = darwinConfiguration "m1-mbp" "jademeskill";
      };

      homeConfigurations = {
      };

      nixosConfigurations = {
        "disko@single-ext4" = diskoConfiguration "single-ext4";

        "incus" = nixosConfiguration {
          roles = [ "incus" ];
        };

        "media-managers" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "media-managers" ];
        };

        "media-servers" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "media-servers" ];
        };

        "vaultwarden" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "vaultwarden" ];
        };
      };
    };
}
