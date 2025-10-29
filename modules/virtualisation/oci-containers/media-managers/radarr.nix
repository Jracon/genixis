{
  networking.firewall.allowedTCPPorts = [
    7878
    7879
  ];

  system.activationScripts.create_radarr_directories.text = ''
    mkdir -p /mnt/radarr /mnt/media /mnt/radarr-anime
  '';

  virtualisation.oci-containers.containers = {
    radarr = {
      image = "lscr.io/linuxserver/radarr:latest";

      hostname = "radarr";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "7878:7878"
      ];
      volumes = [
        "/mnt/radarr:/config"
        "/mnt/media:/mnt/media"
      ];
    };
    radarr-anime = {
      image = "lscr.io/linuxserver/radarr:latest";

      hostname = "radarr-anime";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "7879:7878"
      ];
      volumes = [
        "/mnt/radarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];
    };
  };
}
