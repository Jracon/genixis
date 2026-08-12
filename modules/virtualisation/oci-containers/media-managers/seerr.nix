{
  networking.firewall.allowedTCPPorts = [
    5055
  ];

  system.activationScripts.create_seerr_directory.text = ''
    mkdir -p /mnt/seerr
  '';

  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:latest";

    hostname = "seerr";
    pull = "newer";

    environment = {
      TZ = "America/Phoenix";
    };
    ports = [
      "5055:5055"
    ];
    volumes = [
      "/mnt/seerr:/app/config"
    ];
  };
}
