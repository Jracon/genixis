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
              values = if config ? ${key} && config.${key} != null then
                if builtins.isList config.${key} then config.${key} else [ config.${key} ]
                else [ ];
            in 
              builtins.concatMap (value: 
                let 
                  path = ./${key}/${toString value};
                  filePath = path + ".nix";
                in 
                  if builtins.pathExists filePath then 
                    builtins.trace "Found file: ${toString filePath}" [ filePath ]
                  else if builtins.pathExists path && builtins.isPath path then 
                    if builtins.pathExists (toString path) && builtins.readDir (toString path) != {} then 
                      let 
                        files = builtins.attrNames (builtins.readDir path); 
                        nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) files; 
                      in 
                        builtins.trace "Found directory: ${toString path} with nix files: ${builtins.toJSON nixFiles}"
                        (builtins.map (name: path + "/${name}") nixFiles)
                    else 
                      builtins.trace "Skipping empty directory: ${toString path}" []
                  else 
                    builtins.trace "Path not found: ${toString path}" []
              ) values 
          ) (builtins.attrNames config);
        in
          builtins.trace "Final modules: ${builtins.toJSON modules}" modules;
        
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
      
      diskoConfiguration = layout: disks: 
        nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit disks;
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
            disko.nixosModules.disko
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
        "test" = nixosConfiguration "test_hostname" {disk-layouts = "single-ext4";} {disks = [ "/dev/sda" ];};
        "disko@test" = diskoConfiguration "single-ext4" [ "/dev/sda" ];
        
        "incus" = nixosConfiguration "incus" {roles = [ "incus" ]; disk-layouts = "single-ext4";} {disks = [ "/dev/sda" ]; interfaces = [ "eno1" ];};
        "docker" = nixosConfiguration "docker" {roles = [ "docker" ]; containers = [ "media-servers" ];} {};
      };
    };
}
