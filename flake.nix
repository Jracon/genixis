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

    invidious = {
      url = "github:iv-org/invidious";
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

    themes = {
      url = "git+https://forgejo.local.jracon.xyz/jracon/themes";
      inputs.nixpkgs.follows = "nixpkgs";
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
      invidious,
      llm-agents,
      nix-cachyos-kernel,
      nix-darwin,
      nix-homebrew,
      nix-vscode-extensions,
      nixos-wsl,
      nixpkgs,
      themes,
      ...
    }:
    let
      # expands each directory in a module list into every .nix file beneath it (recursively);
      # files and non-path modules pass through, and a mistyped path fails evaluation
      expandModules = nixpkgs.lib.concatMap (
        module:
        if builtins.isPath module && nixpkgs.lib.pathIsDirectory module then
          nixpkgs.lib.filter (nixpkgs.lib.hasSuffix ".nix") (nixpkgs.lib.filesystem.listFilesRecursive module)
        else
          [
            module
          ]
      );

      generateDiskoModules =
        local:
        if local ? "disk-layout" then
          [
            ./disk-layouts/${local.disk-layout}.nix

            disko.nixosModules.disko
          ]
        else
          [ ];

      # Home Manager program set is chosen by platform: Darwin -> cli+darwin+gui; NixOS -> cli+nixos (+gui)
      homeModules =
        {
          gui,
          isDarwin,
          palette ? "violet",
        }:
        expandModules (
          [
            ./home.nix
            ./modules/programs/cli

            agenix.homeManagerModules.default
            {
              _module.args = {
                inherit themes;
              };
              genixis.palette.name = palette;
            }
          ]
          ++ (
            if isDarwin then
              [
                ./modules/programs/darwin
                ./modules/programs/gui
              ]
            else if gui then
              [
                ./modules/programs/gui
                ./modules/programs/nixos
              ]
            else
              [
                ./modules/programs/nixos
              ]
          )
        );

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
            ./common/base.nix
            ./common/darwin.nix
            ./common/home-manager.nix
            ./common/homebrew.nix
            ./common/llm-agents.nix
            ./common/nixpkgs.nix

            agenix.darwinModules.default
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
              nix-vscode-extensions
              self
              system
              user
              ;

            homeModules = homeModules {
              gui = true;
              isDarwin = true;
            };
            homeUsers = [
              user.name
            ];
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
            generateDiskoModules local
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
          system = builtins.currentSystem;
          pkgs = nixpkgs.legacyPackages.${system};
        in
        # standalone, for non-NixOS machines; NixOS and Darwin hosts get Home Manager through their system config
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          extraSpecialArgs = {
            inherit nix-vscode-extensions;
          };
          modules = [
            ./common/nixpkgs.nix

            {
              home.username = username;
              programs.home-manager.enable = true; # provides the CLI used by rehome
            }
          ]
          ++ homeModules {
            gui = local.gui or false;
            isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
          }
          ++ nixpkgs.lib.optional (builtins.pathExists ./users/${username}.nix) ./users/${username}.nix;
        };

      nixosConfiguration =
        {
          homeUsers ? [ ],
          palette ? "violet",
          roleModules,
        }:
        hostModules:
        let
          local = if builtins.pathExists /etc/nixos/local.nix then import /etc/nixos/local.nix else { };
          system = "x86_64-linux";
        in
        nixpkgs.lib.nixosSystem {
          inherit system;

          modules = [
            ./common/base.nix
            ./common/home-manager.nix
            ./common/nixos.nix
            ./common/nixpkgs.nix

            home-manager.nixosModules.home-manager
          ]
          ++ expandModules (roleModules ++ hostModules)
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
          ++ generateDiskoModules local;
          specialArgs = {
            inherit
              agenix
              invidious
              llm-agents
              local
              nix-cachyos-kernel
              nix-vscode-extensions
              system
              ;

            homeModules = homeModules {
              inherit palette;

              gui = local.gui or false;
              isDarwin = false;
            };
            homeUsers = [
              "root"
            ]
            ++ homeUsers;
          };
        };

      desktopConfiguration = nixosConfiguration {
        homeUsers = [
          users.jademeskill.name
        ];
        palette = "moss";
        roleModules = [
          ./common/gaming.nix
          ./common/llm-agents.nix
          ./common/plasma.nix
          ./common/ssh.nix
        ];
      };

      serverRoleModules = [
        ./common/agenix.nix
        ./common/ssh.nix

        agenix.nixosModules.default
      ];

      serverConfiguration = nixosConfiguration {
        roleModules = serverRoleModules;
      };

      # a server with a "dev" user for remote development
      devServerConfiguration = nixosConfiguration {
        homeUsers = [
          "dev"
        ];
        roleModules = serverRoleModules;
      };

      wslConfiguration = nixosConfiguration {
        homeUsers = [
          users.nixos.name
        ];
        roleModules = [
          ./common/llm-agents.nix
          ./common/wsl.nix

          nixos-wsl.nixosModules.default
        ];
      };
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
        bare = serverConfiguration [ ];
        desktop = desktopConfiguration [
          ./modules/hardware/cachyos-kernel.nix
          ./modules/hardware/windows-dual-boot.nix
        ];
        disko = diskoConfiguration;
        media = serverConfiguration [
          ./modules/services/syncthing.nix
          ./modules/services/tailscale
          ./modules/virtualisation/oci-containers/media-downloaders
          ./modules/virtualisation/oci-containers/media-managers
          ./modules/virtualisation/oci-containers/media-servers
          ./modules/virtualisation/podman.nix
        ];
        services = devServerConfiguration [
          ./modules/services/rclone-webdav.nix
          ./modules/services/syncthing.nix
          ./modules/services/tailscale
          ./modules/virtualisation/oci-containers/caddy
          ./modules/virtualisation/oci-containers/continuwuity
          ./modules/virtualisation/oci-containers/forgejo
          ./modules/virtualisation/oci-containers/invidious
          ./modules/virtualisation/oci-containers/languagetool.nix
          ./modules/virtualisation/oci-containers/mealie
          ./modules/virtualisation/oci-containers/monica
          ./modules/virtualisation/oci-containers/radicale
          ./modules/virtualisation/oci-containers/vaultwarden
          ./modules/virtualisation/podman.nix
        ];
        wsl = wslConfiguration [ ];
      };
    };
}
