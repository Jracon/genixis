{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [
      8191
      9696
    ];
    allowedUDPPorts = [
      8191
      9696
    ];
  };

  virtualisation.oci-containers.containers = {
    flaresolverr = {
      hostname = "flaresolverr";
      image = "ghcr.io/flaresolverr/flaresolverr:latest";

      environment = {
        TZ = "America/Phoenix";
      };
      ports = [
        "8191:8191"
      ];
      pull = "always";
    };

    prowlarr = {
      hostname = "prowlarr";
      image = "lscr.io/linuxserver/prowlarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "9696:9696"
      ];
      pull = "always";
      volumes = [
        "/mnt/media/data/prowlarr:/config"
      ];
    };
  };
}
