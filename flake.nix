{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    agenix = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:ryantm/agenix";
    };

    disko = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/disko/latest";
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager/release-25.05";
    };

    nix-darwin = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs =
    {
      self,
      agenix,
      disko,
      home-manager,
      homebrew-cask,
      homebrew-core,
      nixpkgs-darwin,
      nixpkgs-stable,
      nixpkgs,
      nix-darwin,
      nix-homebrew,
      ...
    }@inputs:

    let
      generateConfigModules =
        config:
        let
          configKeys = builtins.attrNames config;
          filteredKeys = builtins.filter (k: k != "containers") configKeys;

          modules = builtins.concatMap (
            key:
            let
              values =
                if config ? ${key} then
                  if builtins.isList config.${key} then config.${key} else [ config.${key} ]
                else
                  [ ];
            in
            builtins.concatMap (
              value:
              let
                basePath =
                  if key == "modules" then ./${key}/${toString value} else ./modules/${key}/${toString value};
                filePath = basePath + ".nix";
              in
              if builtins.pathExists filePath then
                [ filePath ]
              else if builtins.pathExists basePath && builtins.isPath basePath then
                let
                  entries = builtins.readDir basePath;
                  nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
                    builtins.attrNames entries
                  );
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

      generateDiskoModules =
        local:
        if local ? "disk-layout" then
          [
            disko.nixosModules.disko
            ./disk-layouts/${local.disk-layout}.nix
          ]
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

      darwinConfiguration =
        hostname:
        let
          system = "aarch64-darwin";
        in
        nix-darwin.lib.darwinSystem {
          inherit system;

          specialArgs = {
            inherit self agenix system;
            inherit homebrew-cask homebrew-core;
          };

          modules = [
            ./common/darwin.nix
            ./common/enable-flakes.nix
            ./common/nix.nix
            ./common/shell.nix

            agenix.nixosModules.default
            ./common/agenix.nix

            home-manager.darwinModules.home-manager
            ./common/home-manager.nix

            nix-homebrew.darwinModules.nix-homebrew
            ./common/homebrew.nix
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

      homeManagerConfiguration =
        username:
        let
          local =
            if builtins.pathExists /etc/nixos/local.nix then
              import /etc/nixos/local.nix
            else if builtins.pathExists /etc/nix-darwin/local.nix then
              import /etc/nix-darwin/local.nix
            else
              { };
          system = builtins.currentSystem;
          pkgs = import nixpkgs { inherit system; };
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;

          extraSpecialArgs = {
            user = users.${username};
          };

          modules =
            [
              ./home.nix

              ./users/${username}.nix
            ]
            ++ generateConfigModules {
              programs =
                [ "cli" ]
                ++ (
                  if pkgs.stdenv.isDarwin then
                    [
                      "gui"
                      "darwin"
                    ]
                  else if (local ? gui && local.gui) then
                    [ "gui" ]
                  else
                    [ ]
                );
            };
        };

      nixosConfiguration =
        config:
        let
          containerNames = if config ? containers then config.containers else [ ];
          lib = pkgs.lib;
          local = if builtins.pathExists /etc/nixos/local.nix then import /etc/nixos/local.nix else { };
          pkgs = import nixpkgs { inherit system; };
          system = builtins.currentSystem;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = {
            inherit local system;
          };

          modules =
            [
              /etc/nixos/configuration.nix

              ./common/enable-flakes.nix
              ./common/minimal.nix
              ./common/nix.nix
              ./common/shell.nix
              ./common/ssh.nix

              agenix.nixosModules.default
              ./common/agenix.nix

              home-manager.nixosModules.home-manager
              ./common/home-manager.nix
            ]
            ++ generateConfigModules config
            ++ generateDiskoModules local
            ++ (
              if containerNames != [ ] then
                [
                  import
                  ./templates/node.nix
                  {
                    inherit
                      config
                      containerNames
                      lib
                      local
                      pkgs
                      ;
                  }
                ]
              else
                [ ]
            );
        };
    in
    {
      darwinConfigurations = {
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

        "media" = nixosConfiguration {
          containers = [
            "media-downloaders"
            "media-managers"
            "media-servers"
          ];
          services = [ "tailscale" ];
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
