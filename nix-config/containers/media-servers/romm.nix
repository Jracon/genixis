{
  ...
}:

{
  age.secrets = {
    romm_environment = {
      file = ./romm/environment.age;
      mode = "600";
    };
    romm-db_environment = {
      file = ./romm/db_environment.age;
      mode = "600";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      9999
    ];
  };

  virtualisation.oci-containers.containers = {
    romm = {
      hostname = "romm";
      image = "rommapp/romm:latest";

      dependsOn = [
        "romm-db"
      ];
      environmentFiles = [
        config.age.secrets.romm_environment.path
      ];
      ports = [
        "9999:8080"
      ];
      pull = "always";
      volumes = [
        "romm_resources:/romm/resources"
        "romm_redis_data:/redis-data"
        "/mnt/media/games:/romm/library"
        "/dummy:/romm/library/.stfolder"
        "/dummy:/romm/library/Amiibos"
        "/dummy:/romm/library/citra"
        "/dummy:/romm/library/dolphin"
        "/dummy:/romm/library/ryujinx"
        "/dummy:/romm/library/windows"
        "/dummy:/romm/library/yuzu"
        "/mnt/media/data/romm/assets:/romm/assets"
        "/mnt/media/data/romm/config:/romm/config"
      ];
    };

    romm-db = {
      hostname = "romm-db";
      image = "mariadb:latest";

      environmentFiles = [
        config.age.secrets.romm-db_environment.path
      ];
      volumes = [
        "mysql_data:/var/lib/mysql"
      ];
    };
  };
}