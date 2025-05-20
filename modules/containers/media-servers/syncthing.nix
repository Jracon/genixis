{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8384
      22000
    ];

    allowedUDPPorts = [
      21027
    ];
  };

  virtualisation.oci-containers.containers.syncthing = {
    image = "lscr.io/linuxserver/syncthing:latest";
    pull = "newer";
    hostname = "syncthing";

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    ports = [
      "8384:8384"
      "21027:21027/udp"
      "22000:22000"
    ];
  };
}
