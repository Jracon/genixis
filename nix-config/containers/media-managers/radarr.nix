{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      7878
      7879
    ];
  };

  system.activationScripts = {
    create_radarr_directories.text = ''
      mkdir -p /mnt/media/data/radarr /mnt/media/data/radarr-anime
    '';
  };

  virtualisation.oci-containers.containers = {
    radarr = {
      hostname = "radarr";
      image = "lscr.io/linuxserver/radarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "7878:7878"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/radarr:/config"
      ];
    };

    radarr-anime = {
      hostname = "radarr-anime";
      image = "lscr.io/linuxserver/radarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "7879:7878"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/radarr-anime:/config"
      ];
    };
  };
}
