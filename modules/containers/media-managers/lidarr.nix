{
  config, 
  ...
}:

{
  age.secrets = {
    lidatube_environment = {
      file = ./lidatube/environment.age;
      # mode = "600";
    };
  };

  networking.firewall.allowedTCPPorts = [
    5001
    8686
  ];

  system.activationScripts = {
    create_lidarr_directory.text = ''
      mkdir -p /mnt/lidarr /mnt/media/music
    '';

    create_lidatube_directories.text = ''
      mkdir -p /mnt/lidatube /mnt/media/music
    '';
  };

  virtualisation.oci-containers.containers = {
    lidarr = {
      image = "lscr.io/linuxserver/lidarr:latest";
      pull = "newer";
      hostname = "lidarr";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/lidarr:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "8686:8686"
      ];
    };

    lidatube = {
      image = "thewicklowwolf/lidatube:latest";
      pull = "newer";
      hostname = "lidatube";

      environmentFiles = [
        config.age.secrets.lidatube_environment.path
      ];

      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "/mnt/lidatube:/lidatube/config"
        "/mnt/media/music:/lidatube/downloads"
      ];

      ports = [
        "5001:5000"
      ];
    };
  };
}
