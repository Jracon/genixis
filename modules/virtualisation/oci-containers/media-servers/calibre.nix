{
  networking.firewall.allowedTCPPorts = [
    8181
  ];

  system.activationScripts.create_calibre_directories.text = ''
    mkdir -p /mnt/calibre /mnt/media/calibre-library && chown -R 1000:1000 /mnt/calibre /mnt/media/calibre-library
  '';

  virtualisation.oci-containers.containers.calibre = {
    image = "lscr.io/linuxserver/calibre:latest";

    hostname = "calibre";
    pull = "newer";

    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "8081:8080"
      "8082:8081"
      "8181:8181"
    ];
    volumes = [
      "/mnt/calibre:/config"
      "/mnt/media/calibre-library:/calibre-library"
    ];
  };
}
