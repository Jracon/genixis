{
  config,
  lib,
  pkgs,
  ...
}:

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
      pull = "newer";
      hostname = "sonarr";
      user = "1000:1000";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/sonarr:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "8989:8989"
      ];
    };

    sonarr-anime = {
      image = "lscr.io/linuxserver/sonarr:latest";
      pull = "newer";
      hostname = "sonarr-anime";
      user = "1000:1000";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/sonarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "8990:8989"
      ];
    };
  };
}
