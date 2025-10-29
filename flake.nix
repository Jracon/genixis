{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
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
    home-manager = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-community/home-manager";
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    nix-darwin = {
      inputs.nixpkgs.follows = "nixpkgs";
      url = "github:nix-darwin/nix-darwin";
    };
  };

  outputs =
    {
      self,
      agenix,
      disko,
      home-manager,
      homebrew-cask,
      homebrew-core,
      nix-darwin,
      nix-homebrew,
      nixpkgs-darwin,
      nixpkgs-stable,
      nixpkgs,
      ...
    }@inputs:
    let
      generateConfigModules =
        config:
        let
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
                # builtins.trace "Found nix files in folder ${toString basePath}: ${toString nixFiles}"
                (builtins.map (name: basePath + "/${name}") nixFiles)
              else
                # builtins.trace "Skipping: no file or folder found at ${toString basePath}"
                [ ]
            ) values
          ) (builtins.attrNames config);
        in
        # builtins.trace "Resolved modules: ${builtins.toString modules}"
        modules;

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
            inherit
              self
              agenix
              homebrew-cask
              homebrew-core
              system
              ;
          };
          modules = [
            ./common/agenix.nix
            ./common/darwin.nix
            ./common/enable-flakes.nix
            ./common/home-manager.nix
            ./common/homebrew.nix
            ./common/minimal.nix
            ./common/nix.nix

            agenix.nixosModules.default
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
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
            ./disk-layouts/${local.disk-layout}.nix

            /tmp/etc/nixos/configuration.nix

            disko.nixosModules.disko
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
          pkgs = import nixpkgs { inherit system; };
          system = builtins.currentSystem;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs;

          extraSpecialArgs = {
            user = users.${username};
          };
          modules = [
            ./home.nix
            ./users/${username}.nix
          ]
          ++ generateConfigModules {
            programs = [
              "cli"
            ]
            ++ (
              if pkgs.stdenv.isDarwin then
                [
                  "darwin"
                  "gui"
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
            inherit
              agenix
              containerNames
              local
              system
              ;
          };

          modules = [
            ./common/agenix.nix
            ./common/enable-flakes.nix
            ./common/home-manager.nix
            ./common/minimal.nix
            ./common/nix.nix
            ./common/nixos.nix
            ./common/ssh.nix

            /etc/nixos/configuration.nix

            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
          ]
          ++ generateConfigModules config
          ++ generateDiskoModules local;
        };
    in
    {
      darwinConfigurations = {
        "m2pro-mbp" = darwinConfiguration "m2pro-mbp";
      };
      homeConfigurations = {
        "jademeskill" = homeManagerConfiguration "jademeskill";
        "root" = homeManagerConfiguration "root";
      };
      nixosConfigurations = {
        "disko" = diskoConfiguration;
        "bare" = nixosConfiguration { };
        "media" = nixosConfiguration {
          services = [ "tailscale" ];
          virtualisation = [
            "podman"
            "oci-containers/media-downloaders"
            "oci-containers/media-managers"
            "oci-containers/media-servers"
          ];
        };
        "services" = nixosConfiguration {
          services = [ "tailscale" ];
          virtualisation = [
            "podman"
            "oci-containers/caddy"
            "oci-containers/invidious"
            "oci-containers/languagetool"
            "oci-containers/mealie"
            "oci-containers/monica"
            "oci-containers/vaultwarden"
          ];
        };
      };
    };
}
