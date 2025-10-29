{
  networking.firewall.allowedTCPPorts = [
    8191
    9696
  ];

  system.activationScripts.create_prowlarr_directory.text = ''
    mkdir -p /mnt/prowlarr
  '';

  virtualisation.oci-containers.containers = {
    flaresolverr = {
      image = "ghcr.io/flaresolverr/flaresolverr:latest";

      hostname = "flaresolverr";
      pull = "newer";

      environment = {
        TZ = "America/Phoenix";
      };
      ports = [
        "8191:8191"
      ];
    };
    prowlarr = {
      image = "lscr.io/linuxserver/prowlarr:latest";

      hostname = "prowlarr";
      pull = "newer";

      environment = {
        PGID = "1000";
        PUID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [
        "9696:9696"
      ];
      volumes = [
        "/mnt/prowlarr:/config"
      ];
    };
  };
}
