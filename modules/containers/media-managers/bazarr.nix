{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    6767
    6768
  ];

  system.activationScripts.create_bazarr_directories.text = ''
    mkdir -p /mnt/bazarr /mnt/media /mnt/bazarr-anime
  '';

  virtualisation.oci-containers.containers = {
    bazarr = {
      image = "lscr.io/linuxserver/bazarr:latest";
      pull = "newer";
      hostname = "bazarr";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/bazarr:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "6767:6767"
      ];
    };

    bazarr-anime = {
      image = "lscr.io/linuxserver/bazarr:latest";
      pull = "newer";
      hostname = "bazarr-anime";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/bazarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];

      ports = [
        "6768:6767"
      ];
    };
  };
}
