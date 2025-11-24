{
  networking.firewall = {
    allowedTCPPorts = [
      8384
      22000
    ];
    allowedUDPPorts = [
      21027
      22000
    ];
  };

  virtualisation.oci-containers.containers.syncthing = {
    image = "linuxserver/syncthing:latest";

    hostname = "syncthing";
    pull = "newer";

    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "8384:8384"
      "21027:21027/udp"
      "22000:22000"
      "22000:22000/udp"
    ];
    volumes = [
      "/mnt/syncthing:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
