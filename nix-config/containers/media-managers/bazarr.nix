{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      6767
      6768
    ];
  };

  virtualisation.oci-containers.containers = {
    bazarr = {
      hostname = "bazarr";
      image = "lscr.io/linuxserver/bazarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "6767:6767"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/bazarr:/config"
      ];
    };

    bazarr-anime = {
      hostname = "bazarr-anime";
      image = "lscr.io/linuxserver/bazarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "6768:6767"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/bazarr-anime:/config"
      ];
    };
  };
}
