{
  networking.firewall.allowedTCPPorts = [
    8112
  ];

  system.activationScripts.create_deluge_directories.text = ''
    mkdir -p /mnt/deluge /mnt/media/downloads/torrents/incomplete /mnt/media/downloads/torrents/complete
  '';

  virtualisation.oci-containers.containers.deluge = {
    image = "lscr.io/linuxserver/deluge:latest";

    hostname = "deluge";
    pull = "newer";

    dependsOn = [
      "gluetun"
    ];
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    networks = [
      "gluetun-network"
    ];
    ports = [
      "8112:8112"
    ];
    volumes = [
      "gluetun:/pia:ro"
      "/mnt/media:/mnt/media"
      "/mnt/deluge:/config"
    ];
  };
}
