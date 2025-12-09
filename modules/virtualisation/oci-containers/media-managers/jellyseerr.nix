{
  networking.firewall.allowedTCPPorts = [
    5055
  ];

  system.activationScripts.create_jellyseerr_directory.text = ''
    mkdir -p /mnt/jellyseerr
  '';

  virtualisation.oci-containers.containers.jellyseerr = {
    image = "ghcr.io/fallenbagel/jellyseerr:latest";

    hostname = "jellyseerr";
    pull = "newer";

    environment = {
      TZ = "America/Phoenix";
    };
    ports = [
      "5055:5055"
    ];
    volumes = [
      "/mnt/jellyseerr:/app/config"
    ];
  };
}
