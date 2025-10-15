{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    8081
  ];

  system.activationScripts.create_calibre_directories.text = ''
    mkdir -p /mnt/media/downloads/cwabd /mnt/calibre /mnt/calibre-library
  '';

  virtualisation.oci-containers.containers.calibre = {
    image = "crocodilestick/calibre-web-automated:latest";
    pull = "newer";
    hostname = "calibre-web-automated";

    environment = {
      DOCKER_MODS = "lscr.io/linuxserver/mods:universal-calibre-v7.16.0";
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    volumes = [
      "/mnt/calibre:/config"
      "/mnt/calibre-library:/calibre-library"
      "/mnt/media/downloads/cwabd:/cwa-book-ingest"
    ];

    ports = [
      "8081:8083"
    ];
  };
}
