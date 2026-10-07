{
  networking.firewall.allowedTCPPorts = [
    8083
  ];

  system.activationScripts.create_calibre-web-automated_directory.text = ''
    mkdir -p /mnt/calibre-web-automated && chown -R 1000:1000 /mnt/calibre-web-automated
  '';

  virtualisation.oci-containers.containers.calibre-web-automated = {
    image = "docker.io/crocodilestick/calibre-web-automated:latest";

    hostname = "calibre-web-automated";
    pull = "newer";

    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "8083:8083"
    ];
    volumes = [
      "/mnt/calibre-web-automated:/config"
      "/mnt/calibre/.config/calibre/plugins:/config/.config/calibre/plugins"
      "/mnt/media/books:/mnt/media/books"
      "/mnt/media/data/calibre-library:/calibre-library"
      "/mnt/media/downloads/shelfmark:/cwa-book-ingest"
    ];
  };
}
