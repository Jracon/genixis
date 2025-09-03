{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets = {
    romm_environment = {
      file = ./romm/environment.age;
      # mode = "600";
    };

    romm-db_environment = {
      file = ./romm/db_environment.age;
      # mode = "600";
    };
  };

  networking.firewall.allowedTCPPorts = [
    9999
  ];

  system.activationScripts = {
    create_romm_directories.text = ''
      mkdir -p /mnt/romm/assets /mnt/romm/config /mnt/media/games /dummy
    '';

    create_romm-network.text = ''
      ${pkgs.podman}/bin/podman network create romm-network --ignore
    '';
  };

  virtualisation.oci-containers.containers = {
    romm = {
      image = "rommapp/romm:latest";
      pull = "newer";
      hostname = "romm";

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
        "romm_resources:/romm/resources"
        "romm_redis_data:/redis-data"
        "/mnt/romm/assets:/romm/assets"
        "/mnt/romm/config:/romm/config"
        "/mnt/media/games:/romm/library"
        "/dummy:/romm/library/Amiibos"
      ];
    };

    romm-db = {
      image = "mariadb:latest";
      pull = "newer";
      hostname = "romm-db";

      environmentFiles = [
        config.age.secrets.romm-db_environment.path
      ];

      volumes = [
        "mysql_data:/var/lib/mysql"
      ];

      networks = [
        "romm-network"
      ];
    };
  };
}
