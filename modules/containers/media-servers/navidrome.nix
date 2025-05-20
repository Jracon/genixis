{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    4533
  ];

  system.activationScripts.create_navidrome_directories.text = ''
    mkdir -p /mnt/navidrome /mnt/media/music && chown 1000:1000 -R /mnt/navidrome
  '';

  virtualisation.oci-containers.containers.navidrome = {
    image = "deluan/navidrome:latest";
    pull = "newer";
    hostname = "navidrome";
    user = "1000:1000";

    environment = {
      ND_BASEURL = "";
      ND_LOGLEVEL = "info";
      ND_SCANSCHEDULE = "1h";
      ND_SESSIONTIMEOUT = "24h";
    };

    volumes = [
      "/mnt/navidrome:/data"
      "/mnt/media/music:/music:ro"
    ];

    ports = [
      "4533:4533"
    ];
  };
}
