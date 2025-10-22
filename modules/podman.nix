{ config, lib, ... }:
with lib;
let
  cfg = config.virtualisation;
in
{
  options.virtualisation.guestOciContainers = mkOption {
    type = types.attrsOf (types.submodule ({ ... }: cfg.oci-containers.containers.type.getSubModules));
    default = { };
    description = "Container definitions intended for the guest system.";
  };

  virtualisation = {
    oci-containers.backend = "podman";

    podman = {
      enable = true;

      autoPrune = {
        enable = true;
        dates = "daily";

        flags = [
          "--all"
        ];
      };
    };
  };
}
