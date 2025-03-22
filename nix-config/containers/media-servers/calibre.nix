{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8081
    ];
  };

  virtualisation.oci-containers.containers = {
    calibre = {
      hostname = "calibre-web-automated";
      image = "crocodilestick/calibre-web-automated:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";

        DOCKER_MODS = "lscr.io/linuxserver/mods:universal-calibre-v7.16.0";
      };
      ports = [
        "8081:8083"
      ];
      pull = "always";
      volumes = [
        "/mnt/media/completed/books:/cwa-book-ingest"
        "/mnt/media/data/calibre:/config"
        "/mnt/media/data/calibre-library:/calibre-library"
      ];
    };
  };
}
