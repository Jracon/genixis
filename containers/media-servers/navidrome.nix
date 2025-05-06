{
  ...
}:

{
  networking.firewall.allowedTCPPorts = [
    4533
  ];

  system.activationScripts.create_navidrome_directories.text = ''
    mkdir -p /mnt/media/data/navidrome /mnt/media/music && chown 1000:1000 -R /mnt/media/data/navidrome
  '';

  virtualisation.oci-containers.containers.navidrome = {
    hostname = "navidrome";
    image = "deluan/navidrome:latest";

    environment = {
      ND_BASEURL = "";
      ND_LOGLEVEL = "info";
      ND_SCANSCHEDULE = "1h";
      ND_SESSIONTIMEOUT = "24h";
    };
    ports = [
      "4533:4533"
    ];
    pull = "newer";
    user = "1000:1000";
    volumes = [
      "/mnt/media/data/navidrome:/data"
      "/mnt/media/music:/music:ro"
    ];
  };
}
