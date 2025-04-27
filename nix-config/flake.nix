{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    agenix = { 
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ryantm/agenix";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko/latest";
    };

    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };

    nix-darwin = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:lnl7/nix-darwin";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = {
    self,
    agenix,
    disko,
    home-manager,
    nix-darwin,
    nixpkgs,
    nixpkgs-darwin,
    nixpkgs-stable,
    ...
  } @ inputs:

  let
    generateConfigModules = config: local:
      let
        modules = builtins.concatMap (
          key:
          let
            values = if config ? ${key} then (
                       if builtins.isList config.${key} then 
                         config.${key} 
                       else 
                         [ config.${key} ]
                      )
                     else 
                       [ ];
          in
            builtins.concatMap (
              value:
              let
                path = ./${key}/${toString value};
                filePath = path + ".nix";
              in
                if builtins.pathExists filePath then 
                  [ filePath ]
                else if builtins.pathExists path && builtins.isPath path then 
                let
                  nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
                    builtins.attrNames (builtins.readDir path)
                  );
                in
                  builtins.map (name: path + "/${name}") nixFiles
                else 
                  [ ]
            ) values
        ) (builtins.attrNames config);

        diskoModules = if local ? "disk-layout" then 
                         [ disko.nixosModules.disko ./disk-layouts/${local.disk-layout}.nix ] 
                       else 
                         [ ];
      in
        modules ++ diskoModules;

    users = {
      jimeskill = {
        name = "jimeskill";
      };
    };

    darwinConfiguration = hostname:
      let 
        system = "aarch64-darwin";
      in
        nix-darwin.lib.darwinSystem {
          inherit system;

          specialArgs = {
            inherit self agenix system;
          };

          modules = [
            ./common/agenix.nix
            ./common/darwin.nix
            ./common/enable-flakes.nix
            ./common/home-manager.nix

            agenix.nixosModules.default
            home-manager.darwinModules.home-manager
          ];
        };

    diskoConfiguration = 
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
            ./disk-layouts/${local.disk-layout}.nix
          ];
        };

    homeManagerConfiguration = username:
      let 
        local = if builtins.pathExists /etc/nixos/local.nix then 
                  import /etc/nixos/local.nix
                else 
                  {};
        system = builtins.currentSystem;
        pkgs = import nixpkgs { inherit system; };
      in
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;

          extraSpecialArgs = {
            user = users.${username};
          };

          modules = [
            ./users/${username}.nix
            
            ./users/home.nix
            ./users/programs.nix
            
          ] ++ (if local ? desktop && local.desktop then [ ./users/modules/wezterm.nix ] else []);
        };

    nixosConfiguration = config:
      let
        local = if builtins.pathExists /etc/nixos/local.nix then 
                  import /etc/nixos/local.nix
                else 
                  {};
        system = "x86_64-linux";
      in
        nixpkgs.lib.nixosSystem {
          inherit system; 
          
          specialArgs = {
            inherit agenix local system;
          };

          modules = [
            /etc/nixos/configuration.nix

            ./common/agenix.nix
            ./common/enable-flakes.nix
            ./common/home-manager.nix
            ./common/minimal.nix
            ./common/ssh.nix

            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
          ] ++ generateConfigModules config local;
        };
  in
    {
      darwinConfigurations = {
        "m1-mbp" = darwinConfiguration "m1-mbp";
      };

      homeConfigurations = {
        "jademeskill" = homeManagerConfiguration "jademeskill";
      };

      nixosConfigurations = {
        "disko" = diskoConfiguration;

        "bare" = nixosConfiguration { };

        "caddy" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "caddy" ];
        };

        "incus" = nixosConfiguration {
          roles = [ "incus" "tailscale" ];
        };

        "languagetool" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "languagetool" ];
        };

        "mealie" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "mealie" ];
        };

        "media-downloaders" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "media-downloaders" ];
        };

        "media-managers" = nixosConfiguration {
          roles = [ "podman" "tailscale" ];
          containers = [ "media-managers" ];
        };

        "media-servers" = nixosConfiguration {
          roles = [ "podman" "tailscale" ];
          containers = [ "media-servers" ];
        };

        "vaultwarden" = nixosConfiguration {
          roles = [ "podman" ];
          containers = [ "vaultwarden" ];
        };
      };
    };
}
