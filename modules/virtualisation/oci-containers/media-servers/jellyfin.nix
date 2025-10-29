{
  networking.firewall = {
    allowedTCPPorts = [
      8096
      8920
    ];
    allowedUDPPorts = [
      1900
      7359
    ];
  };

  system.activationScripts.create_jellyfin_directory.text = ''
    mkdir -p /mnt/jellyfin
  '';

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";

    hostname = "jellyfin";
    pull = "newer";

    devices = [
      "/dev/dri:/dev/dri"
    ];
    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "1900:1900/udp"
      "7359:7359/udp"
      "8096:8096"
      "8920:8920"
    ];
    volumes = [
      "/mnt/jellyfin:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
