{
  networking.firewall.allowedTCPPorts = [
    9696
  ];

  system.activationScripts.create_prowlarr_directory.text = ''
    mkdir -p /mnt/prowlarr
  '';

  virtualisation.oci-containers.containers.prowlarr = {
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
}
