{
  networking.firewall.allowedTCPPorts = [
    6767
    6768
  ];

  system.activationScripts.create_bazarr_directories.text = ''
    mkdir -p /mnt/bazarr /mnt/bazarr-anime
  '';

  virtualisation.oci-containers.containers = {
    bazarr = {
      image = "lscr.io/linuxserver/bazarr:latest";

      hostname = "bazarr";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "6767:6767"
      ];
      volumes = [
        "/mnt/bazarr:/config"
        "/mnt/media:/mnt/media"
      ];
    };
    bazarr-anime = {
      image = "lscr.io/linuxserver/bazarr:latest";

      hostname = "bazarr-anime";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "6768:6767"
      ];
      volumes = [
        "/mnt/bazarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];
    };
  };
}
