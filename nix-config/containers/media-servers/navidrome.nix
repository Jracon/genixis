{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      4533
    ];
    allowedUDPPorts = [
      4533
    ];
  };

  virtualisation.oci-containers.containers = {
    navidrome = {
      hostname = "navidrome";
      image = "deluan/navidrome:latest";

      environment = {
        ND_BASEURL = "";
        ND_LOGLEVEL = "info";
        ND_SCANSCHEDULE = "1h";
        ND_SESSIONTIMEOUT = "24h";
      };
      ports = [
        "4533:4533"
      ];
      pull = "always";
      user = "1000:1000";
      volumes = [
        "/mnt/media/data/navidrome:/data"
        "/mnt/media/music:/music:ro"
      ];
    };
  };
}
