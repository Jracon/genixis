{
  networking.firewall.allowedTCPPorts = [
    8989
    8990
  ];

  system.activationScripts.create_sonarr_directories.text = ''
    mkdir -p /mnt/sonarr /mnt/media /mnt/sonarr-anime
  '';

  virtualisation.oci-containers.containers = {
    sonarr = {
      image = "lscr.io/linuxserver/sonarr:latest";

      hostname = "sonarr";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "8989:8989"
      ];
      volumes = [
        "/mnt/sonarr:/config"
        "/mnt/media:/mnt/media"
      ];
    };
    sonarr-anime = {
      image = "lscr.io/linuxserver/sonarr:latest";

      hostname = "sonarr-anime";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "8990:8989"
      ];
      volumes = [
        "/mnt/sonarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];
    };
  };
}
