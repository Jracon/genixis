{
  ...
}:

{
  system.activationScripts.create_deluge_directory.text = ''
    mkdir -p /mnt/deluge
  '';

  virtualisation.oci-containers.containers.deluge = {
    image = "lscr.io/linuxserver/deluge:latest";
    pull = "newer";
    hostname = "deluge";

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    volumes = [
      "gluetun:/pia:ro"
      "/mnt/media:/mnt/media"
      "/mnt/deluge:/config"
    ];

    ports = [
      "8112:8112"
    ];

    dependsOn = [
      "gluetun"
    ];

    networks = [
      "gluetun-network"
    ];
  };
}
