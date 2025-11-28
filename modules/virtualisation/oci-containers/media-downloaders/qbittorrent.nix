{
  networking.firewall = {
    allowedTCPPorts = [
      6881
      8113
    ];
    allowedUDPPorts = [
      6881
    ];
  };

  system.activationScripts.create_qbittorrent_directories.text = ''
    mkdir -p /mnt/qbittorrent /mnt/media/downloads/torrents/incomplete /mnt/media/downloads/torrents/complete
  '';

  virtualisation.oci-containers.containers.qbittorrent = {
    image = "lscr.io/linuxserver/qbittorrent:latest";

    hostname = "qbittorrent";
    pull = "newer";

    dependsOn = [
      "gluetun"
    ];
    environment = {
      PGID = "1000";
      PUID = "1000";
      TORRENTING_PORT = 6881;
      TZ = "America/Phoenix";
      WEBUI_PORT = 8113;
    };
    networks = [
      "gluetun-network"
    ];
    ports = [
      "8113:8113"
      "6881:6881"
      "6881:6881/udp"
    ];
    volumes = [
      "gluetun:/pia:ro"
      "/mnt/media:/mnt/media"
      "/mnt/qbittorrent:/config"
    ];
  };
}
