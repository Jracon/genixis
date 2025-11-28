{
  networking.firewall.allowedTCPPorts = [
    8080
  ];

  system.activationScripts.create_sabnzbd_directories.text = ''
    mkdir -p /mnt/sabnzbd /mnt/media/downloads/usenet/incomplete /mnt/media/downloads/usenet/complete && chown -R 1000:1000 /mnt/sabnzbd /mnt/media/downloads/usenet
  '';

  virtualisation.oci-containers.containers.sabnzbd = {
    image = "lscr.io/linuxserver/sabnzbd:latest";

    hostname = "sabnzbd";
    pull = "newer";

    environment = {
      PGID = "1000";
      PUID = "1000";
      TZ = "America/Phoenix";
    };
    ports = [
      "8080:8080"
    ];
    volumes = [
      "/mnt/media:/mnt/media"
      "/mnt/sabnzbd:/config"
    ];
  };
}
