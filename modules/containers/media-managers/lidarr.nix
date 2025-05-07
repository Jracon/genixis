{
  config, 
  ...
}:

{
  age.secrets = {
    lidatube_environment = {
      file = ./lidatube/environment.age;
      mode = "600";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      5001
      8686
    ];
  };

  system.activationScripts = {
    create_lidarr_directory.text = ''
      mkdir -p /mnt/media/data/lidarr
    '';

    create_lidatube_directories.text = ''
      mkdir -p /mnt/media/data/lidatube /mnt/media/music
    '';
  };

  virtualisation.oci-containers.containers = {
    lidarr = {
      hostname = "lidarr";
      image = "lscr.io/linuxserver/lidarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "8686:8686"
      ];
      pull = "newer";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/lidarr:/config"
      ];
    };

    lidatube = {
      hostname = "lidatube";
      image = "thewicklowwolf/lidatube:latest";

      environmentFiles = [
        config.age.secrets.lidatube_environment.path
      ];
      ports = [
        "5001:5000"
      ];
      pull = "newer";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"

        "/mnt/media/data/lidatube:/lidatube/config"
        "/mnt/media/music:/lidatube/downloads"
      ];
    };
  };
}
