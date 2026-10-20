{
  config,
  pkgs,
  ...
}:

{
  age.secrets = {
    romm-db_environment.file = ./romm/db_environment.age;
    romm_environment.file = ./romm/environment.age;
  };

  networking.firewall.allowedTCPPorts = [
    9999
  ];

  system.activationScripts = {
    create_romm-network.text = ''
      ${pkgs.podman}/bin/podman network create romm-network --ignore
    '';
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
      image = "mariadb:latest";

      hostname = "romm-db";
      pull = "newer";

      environmentFiles = [
        config.age.secrets.romm-db_environment.path
      ];
      extraOptions = [
        "--health-cmd=healthcheck.sh --connect --innodb_initialized"
        "--health-interval=10s"
        "--health-retries=5"
        "--health-start-period=30s"
        "--health-timeout=5s"
      ];
      networks = [
        "romm-network"
      ];
      volumes = [
        "/mnt/romm/mysql:/var/lib/mysql"
      ];
    };
  };
}
