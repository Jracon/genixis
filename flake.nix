{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

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
    generateConfigModules = config:
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
                basePath = if key == "modules" then 
                          ./${key}/${toString value}
                        else 
                          ./modules/${key}/${toString value};
                filePath = basePath + ".nix";
              in
                if builtins.pathExists filePath then 
                  [ filePath ]
                else if builtins.pathExists basePath && builtins.isPath basePath then 
                  let
                    entries = builtins.readDir basePath;
                    nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (builtins.attrNames entries);
                  in
                    builtins.trace "Found nix files in folder ${toString basePath}: ${toString nixFiles}" (
                      builtins.map (name: basePath + "/${name}") nixFiles
                    )
                else 
                  builtins.trace "Skipping: no file or folder found at ${toString basePath}" [ ]
            ) values
        ) (builtins.attrNames config);
      in
        builtins.trace "Resolved modules: ${builtins.toString modules}" modules;

    generateDiskoModules = local: 
      if local ? "disk-layout" then 
        [ disko.nixosModules.disko ./disk-layouts/${local.disk-layout}.nix ] 
      else 
        [ ];

    users = {
      root = {
        name = "root";
      };

      jademeskill = {
        name = "jademeskill";
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
                else if builtins.pathExists /etc/nix-darwin/local.nix then
                  import /etc/nix-darwin/local.nix
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
          ] ++ generateConfigModules {
                  programs = [ "cli" ] ++ (
                    if pkgs.stdenv.isDarwin || (local ? gui && local.gui) then 
                      [ "gui" ] 
                    else 
                      []
                  ); 
                };
        };

    nixosConfiguration = config:
      let
        local = if builtins.pathExists /etc/nixos/local.nix then 
                  import /etc/nixos/local.nix
                else 
                  {};
        system = builtins.currentSystem;
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
          ] ++ generateConfigModules config
            ++ generateDiskoModules local;
        };
  in
    {
      darwinConfigurations = {
        "m1-mbp" = darwinConfiguration "m1-mbp";
        "m2pro-mbp" = darwinConfiguration "m2pro-mbp";
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
          modules = [ "incus" ];
          services = [ "tailscale" ];
        };

        "invidious" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "invidious" ];
          services = [ "tailscale" ];
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
          modules = [ "podman" ]; 
          services = [ "tailscale" ];
          containers = [ "media-servers" ];
        };

        "tailscale" = nixosConfiguration {
          services = [ "tailscale" ];
        };

        "vaultwarden" = nixosConfiguration {
          modules = [ "podman" ];
          containers = [ "vaultwarden" ];
        };
      };
    };
}
