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
      8384
      21027
      22000
    ];
  };

  virtualisation.oci-containers.containers = {
    syncthing = {
      hostname = "syncthing";
      image = "lscr.io/linuxserver/syncthing:latest";

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
      pull = "always";
    };
  };
}
