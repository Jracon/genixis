{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8989
      8990
    ];
  };

  system.activationScripts = {
    create_sonarr_directories.text = ''
      mkdir -p /mnt/media/data/sonarr /mnt/media/data/sonarr-anime
    '';
  };

  virtualisation.oci-containers.containers = {
    sonarr = {
      hostname = "sonarr";
      image = "lscr.io/linuxserver/sonarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "8989:8989"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/sonarr:/config"
      ];
    };

    sonarr-anime = {
      hostname = "sonarr-anime";
      image = "lscr.io/linuxserver/sonarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "8990:8989"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/sonarr-anime:/config"
      ];
    };
  };
}
