{
  description = "My declarative configuration for Nix-enabled systems.";

  inputs = {
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";

    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      self,
      agenix,
      disko,
      home-manager,
      homebrew-cask,
      homebrew-core,
      llm-agents,
      nix-cachyos-kernel,
      nix-darwin,
      nix-homebrew,
      nix-vscode-extensions,
      nixos-wsl,
      nixpkgs,
      ...
    }:
    let
      generateConfigModules =
        config:
        let
          modules = builtins.concatMap (
            key:
            let
              values =
                if config ? ${key} then
                  if builtins.isList config.${key} then
                    config.${key}
                  else
                    [
                      config.${key}
                    ]
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
                [
                  filePath
                ]
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
            ./disk-layouts/${local.disk-layout}.nix

            disko.nixosModules.disko
          ]
        else
          [ ];

      users = {
        jademeskill = {
          name = "jademeskill";
        };
        nixos = {
          name = "nixos";
        };
        root = {
          name = "root";
        };
      };

      darwinConfiguration =
        hostname:
        let
          system = "aarch64-darwin";
          user = users.jademeskill;
        in
        nix-darwin.lib.darwinSystem {
          inherit system;

          modules = [
            ./common/agenix.nix
            ./common/darwin.nix
            ./common/enable-flakes.nix
            ./common/home-manager.nix
            ./common/homebrew.nix
            ./common/llm-agents.nix
            ./common/minimal.nix
            ./common/nix.nix
            ./common/time.nix

            agenix.nixosModules.default
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
          ];
          specialArgs = {
            inherit
              agenix
              homebrew-cask
              homebrew-core
              hostname
              llm-agents
              self
              system
              user
              ;
          };
        };

      diskoConfiguration =
        let
          local =
            if builtins.pathExists /tmp/etc/nixos/local.nix then import /tmp/etc/nixos/local.nix else { };
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;

          modules =
            [ ]
            ++ (
              if local ? "disk-layout" then
                [
                  ./disk-layouts/${local.disk-layout}.nix

                  disko.nixosModules.disko
                ]
              else
                [ ]
            )
            ++ (
              if builtins.pathExists /tmp/etc/nixos/configuration.nix then
                [
                  /tmp/etc/nixos/configuration.nix
                ]
              else
                [
                  ./common/dummy-configuration.nix
                ]
            );
          specialArgs = {
            inherit local;
          };
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
          pkgs = import nixpkgs {
            inherit system;

            overlays = [
              nix-vscode-extensions.overlays.default
            ];
          };
          system = builtins.currentSystem;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

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
              if pkgs.stdenv.hostPlatform.isDarwin then
                [
                  "darwin"
                  "gui"
                ]
              else if (local ? gui && local.gui) then
                [
                  "gui"
                  "nixos"
                ]
              else
                [
                  "nixos"
                ]
            );
          };
        };

      nixosConfiguration =
        roleModules: config:
        let
          containerNames = if config ? containers then config.containers else [ ];
          local = if builtins.pathExists /etc/nixos/local.nix then import /etc/nixos/local.nix else { };
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./common/enable-flakes.nix
            ./common/home-manager.nix
            ./common/minimal.nix
            ./common/nix.nix
            ./common/nixos.nix
            ./common/time.nix

            home-manager.nixosModules.home-manager
          ]
          ++ roleModules
          ++ (
            if builtins.pathExists /etc/nixos/configuration.nix then
              [
                /etc/nixos/configuration.nix
              ]
            else
              [
                ./common/dummy-configuration.nix
              ]
          )
          ++ generateConfigModules config
          ++ generateDiskoModules local;
          specialArgs = {
            inherit
              agenix
              containerNames
              llm-agents
              local
              nix-cachyos-kernel
              system
              ;
          };
        };

      desktopConfiguration = nixosConfiguration [
        ./common/llm-agents.nix
        ./common/ssh.nix
      ];

      serverConfiguration = nixosConfiguration [
        ./common/agenix.nix
        ./common/ssh.nix

        agenix.nixosModules.default
      ];

      wslConfiguration = nixosConfiguration [
        ./common/llm-agents.nix
        ./common/wsl.nix

        nixos-wsl.nixosModules.default
      ];
    in
    {
      darwinConfigurations = {
        m2pro-mbp = darwinConfiguration "m2pro-mbp";
      };
      formatter = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-linux"
      ] (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
      homeConfigurations = {
        jademeskill = homeManagerConfiguration "jademeskill";
        nixos = homeManagerConfiguration "nixos";
        root = homeManagerConfiguration "root";
      };
      nixosConfigurations = {
        bare = serverConfiguration { };
        desktop = desktopConfiguration {
          hardware = [
            "cachyos-kernel"
            "windows-dual-boot"
          ];
        };
        disko = diskoConfiguration;
        media = serverConfiguration {
          services = [
            "tailscale"
          ];
          virtualisation = [
            "oci-containers/media-downloaders"
            "oci-containers/media-managers"
            "oci-containers/media-servers"
            "podman"
          ];
        };
        services = serverConfiguration {
          services = [
            "rclone-webdav"
            "tailscale"
          ];
          virtualisation = [
            "oci-containers/caddy"
            "oci-containers/continuwuity"
            "oci-containers/forgejo"
            "oci-containers/invidious"
            "oci-containers/languagetool"
            "oci-containers/mealie"
            "oci-containers/monica"
            "oci-containers/radicale"
            "oci-containers/vaultwarden"
            "podman"
          ];
        };
        wsl = wslConfiguration { };
      };
    };
}
