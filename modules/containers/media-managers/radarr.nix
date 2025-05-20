{
  ...
}:

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
      pull = "newer";
      hostname = "radarr";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/radarr:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "7878:7878"
      ];
    };

    radarr-anime = {
      image = "lscr.io/linuxserver/radarr:latest";
      pull = "newer";
      hostname = "radarr-anime";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/radarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "7879:7878"
      ];
    };
  };
}
