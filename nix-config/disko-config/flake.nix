{
  description = "";

  inputs = {
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = {
    self, 
    disko, 
    nixpkgs, 
    ...
    } @ inputs:
    let
      nixosConfiguration = layout:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            disko.nixosModules.disko {
              disko.devices = {
                  disk = {
                    main = {
                      type = "disk";
                      device = "";
                      content = {
                        type = "gpt";
                        partitions = {
                          boot = {
                            size = "1M";
                            type = "EF02";
                          };
                          
                          ESP = {
                            size = "1G";
                            type = "EF00";
                            content = {
                              type = "filesystem";
                              format = "vfat";
                              mountpoint = "/boot";
                              mountOptions = [ "umask=0077" ];
                            };
                          };

                          root = {
                            size = "100%";
                            content = {
                              type = "filesystem";
                              format = "ext4";
                              mountpoint = "/";
                            };
                          };
                        };
                      };
                    };
                  };
                };
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        "single_ext4" = nixosConfiguration "single_ext4";
      };
    };
}
