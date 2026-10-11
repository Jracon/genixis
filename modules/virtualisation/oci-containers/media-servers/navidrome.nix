{
  networking.firewall.allowedTCPPorts = [
    4533
  ];

  system.activationScripts.create_navidrome_directory.text = ''
    mkdir -p /mnt/navidrome && chown 1000:1000 -R /mnt/navidrome
  '';

  virtualisation.oci-containers.containers.navidrome = {
    image = "docker.io/deluan/navidrome:latest";

    hostname = "navidrome";
    pull = "newer";
    user = "1000:1000";

    environment = {
      TZ = "America/Phoenix";
    };
    ports = [
      "4533:4533"
    ];
    volumes = [
      "/mnt/navidrome:/data"
      "/mnt/media/music:/music"
    ];
  };
}
