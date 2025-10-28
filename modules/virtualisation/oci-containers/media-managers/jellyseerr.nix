{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    5055
  ];

  system.activationScripts.create_jellyseerr_directory.text = ''
    mkdir -p /mnt/jellyseerr
  '';

  virtualisation.oci-containers.containers.jellyseerr = {
    image = "ghcr.io/fallenbagel/jellyseerr:latest";
    pull = "always";
    hostname = "jellyseerr";

    environment = {
      TZ = "America/Phoenix";
    };

    volumes = [
      "/mnt/jellyseerr:/app/config"
    ];

    ports = [
      "5055:5055"
    ];
  };
}
