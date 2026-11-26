{
  config,
  lib,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;

  # the secret exists only after the owner creates it with `agenix -e` (the
  # pattern of the caddy module). Until then the container runs with the
  # committed configuration and no variables, and the !env_var tags abort
  # the config load and name the missing variables
  environmentExists = builtins.pathExists ./recyclarr/environment.age;
in
{
  age.secrets = lib.mkIf environmentExists {
    recyclarr_environment.file = ./recyclarr/environment.age;
  };

  system.activationScripts.create_recyclarr_directory.text = ''
    mkdir -p /mnt/recyclarr/configs && chown ${oci.mediaUser} -R /mnt/recyclarr
  '';

  virtualisation.oci-containers.containers.recyclarr = {
    image = "ghcr.io/recyclarr/recyclarr";

    hostname = "recyclarr";
    pull = "newer";
    user = oci.mediaUser;

    environment = {
      TZ = config.time.timeZone;
    };
    environmentFiles = lib.mkIf environmentExists [
      config.age.secrets.recyclarr_environment.path
    ];
    volumes = [
      "/mnt/recyclarr:/config"
      "${./recyclarr/recyclarr.yml}:/config/configs/recyclarr.yml"
    ];
  };
}
