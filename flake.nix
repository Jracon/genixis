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

    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    agenix,
    disko,
    home-manager,
    nix-darwin,
    nixpkgs-darwin,
    nixpkgs-stable,
    nixpkgs,
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
                path = if key == "modules" then 
                         ./${key}/${toString value}
                       else 
                         ./modules/${key}/${toString value};
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
      jademeskill = {
        name = "jademeskill";
      };
    };

    darwinConfiguration = hostname:
      let 
        system = builtins.currentSystem;
        # system = "aarch64-darwin";
      in
        nix-darwin.lib.darwinSystem {
          inherit system;

          specialArgs = {
            inherit self agenix system;
          };

          modules = [
            ./common/darwin.nix
            ./common/enable-flakes.nix

            agenix.nixosModules.default
            ./common/agenix.nix

            home-manager.darwinModules.home-manager
            ./common/home-manager.nix
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
            ./home.nix

            ./users/${username}.nix
            
            ./programs/programs.nix
            
          ] ++ (if local ? desktop && local.desktop then [ ./programs/wezterm.nix ] else []);
        };

    nixosConfiguration = config:
      let
        local = if builtins.pathExists /etc/nixos/local.nix then 
                  import /etc/nixos/local.nix
                else 
                  {};
        system = builtins.currentSystem;
        # system = "x86_64-linux";
      in
        nixpkgs.lib.nixosSystem {
          inherit system; 
          
          specialArgs = {
            inherit agenix local system;
          };

          modules = [
            /etc/nixos/configuration.nix

            ./common/enable-flakes.nix
            ./common/minimal.nix
            ./common/ssh.nix

            agenix.nixosModules.default
            ./common/agenix.nix

            home-manager.nixosModules.home-manager
            ./common/home-manager.nix
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
          modules = [ "podman" ];
          containers = [ "caddy" ];
        };

        "incus" = nixosConfiguration {
          modules = [ "incus" "services/tailscale" ];
        };

        "languagetool" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "languagetool" ];
        };

        "mealie" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "mealie" ];
        };

        "media-downloaders" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "media-downloaders" ];
        };

        "media-managers" = nixosConfiguration {
          modules = [ "podman" ]; 
          services = [ "tailscale" ];
          containers = [ "media-managers" ];
        };

        "media-servers" = nixosConfiguration {
          modules = [ "podman" "services/tailscale" ]; 
          containers = [ "media-servers" ];
        };

        "vaultwarden" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "vaultwarden" ];
        };
      };
    };
}
