{
  config,
  pkgs,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  age.secrets = {
    romm-db_environment.file = ./romm/db_environment.age;
    romm_environment.file = ./romm/environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    9999
  ];

  system.activationScripts = {
    create_romm-network.text = oci.networkCreate pkgs.podman "romm";
    create_romm_directories.text = ''
      mkdir -p /mnt/romm/assets /mnt/romm/config /mnt/romm/mysql /mnt/romm/redis-data /mnt/romm/resources /mnt/media/games
    '';
  };

  virtualisation.oci-containers.containers = {
    romm = {
      image = "docker.io/rommapp/romm:latest";

      hostname = "romm";
      pull = "newer";

      dependsOn = [
        "romm-db"
      ];
      environmentFiles = [
        config.age.secrets.romm_environment.path
      ];
      networks = [
        "romm-network"
      ];
      ports = [
        "9999:8080"
      ];
      volumes = [
        "/mnt/romm/redis-data:/redis-data"
        "/mnt/romm/assets:/romm/assets"
        "/mnt/romm/config:/romm/config"
        "${./romm/config.yaml}:/romm/config/config.yml"
        "/mnt/media/games:/romm/library"
        "/mnt/romm/resources:/romm/resources"
      ];
    };

    romm-db = {
      image = "docker.io/mariadb:latest";

      hostname = "romm-db";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.romm-db_environment.path
      ];
      extraOptions = oci.healthcheck { cmd = "healthcheck.sh --connect --innodb_initialized"; };
      networks = [
        "romm-network"
      ];
      volumes = [
        "/mnt/romm/mysql:/var/lib/mysql"
      ];
    };
  };
}
