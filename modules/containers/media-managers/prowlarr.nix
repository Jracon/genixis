{
  ...
}:

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
      pull = "newer";
      hostname = "flaresolverr";

      environment = {
        TZ = "America/Phoenix";
      };
      ports = [
        "8191:8191"
      ];
    };

    prowlarr = {
      image = "lscr.io/linuxserver/prowlarr:latest";
      pull = "newer";
      hostname = "prowlarr";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };

      volumes = [
        "/mnt/prowlarr:/config"
      ];

      ports = [
        "9696:9696"
      ];
    };
  };
}
