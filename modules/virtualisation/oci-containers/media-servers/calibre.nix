{
  networking.firewall.allowedTCPPorts = [
    8081
  ];

  system.activationScripts.create_calibre_directories.text = ''
    mkdir -p /mnt/media/downloads/cwabd /mnt/calibre /mnt/media/calibre-library
  '';

  virtualisation.oci-containers.containers.calibre = {
    image = "crocodilestick/calibre-web-automated:latest";

    hostname = "calibre-web-automated";
    pull = "newer";

    environment = {
      DOCKER_MODS = "lscr.io/linuxserver/mods:universal-calibre-v7.16.0";
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "8081:8083"
    ];
    volumes = [
      "/mnt/calibre:/config"
      "/mnt/media/calibre-library:/calibre-library"
      "/mnt/media/downloads/cwabd:/cwa-book-ingest"
    ];
  };
}
