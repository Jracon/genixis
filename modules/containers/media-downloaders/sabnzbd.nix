{
  ...
}:

{
  system.activationScripts.create_sabnzbd_directories.text = ''
    mkdir -p /mnt/sabnzbd /mnt/media/downloads/usenet/incomplete /mnt/media/downloads/usenet/complete
  '';

  virtualisation.oci-containers.containers.sabnzbd = {
    image = "lscr.io/linuxserver/sabnzbd:latest";
    pull = "newer";
    hostname = "sabnzbd";

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    volumes = [
      "/mnt/media:/mnt/media"
      "/mnt/sabnzbd:/config"
    ];

    ports = [
      "8080:8080"
    ];
  };
}
