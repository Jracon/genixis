{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    8191
    9696
  ];

  system.activationScripts.create_prowlarr_directory.text = ''
    mkdir -p /mnt/media/data/prowlarr
  '';

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
      pull = "newer";
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
      pull = "newer";
      volumes = [
        "/mnt/media/data/prowlarr:/config"
      ];
    };
  };
}
