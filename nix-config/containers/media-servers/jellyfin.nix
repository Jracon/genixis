{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8096
      8920
    ];
    allowedUDPPorts = [
      1900
      7359
      8096
      8920
    ];
  };

  virtualisation.oci-containers.containers = {
    jellyfin = {
      hostname = "jellyfin";
      image = "lscr.io/linuxserver/jellyfin:latest";

      devices = [
        "/dev/dri:/dev/dri"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "1900:1900/udp"
        "7359:7359/udp"
        "8096:8096"
        "8920:8920"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/jellyfin:/config"
      ];
    };
  };
}
