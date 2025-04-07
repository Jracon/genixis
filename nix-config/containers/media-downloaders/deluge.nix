{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    deluge = {
      hostname = "deluge";
      image = "lscr.io/linuxserver/deluge:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      networks = [
        "gluetun-network"
      ];
      ports = [
        "8112:8112"
      ];
      pull = "always";
      volumes = [
        "gluetun:/pia:ro"

        "/mnt/media:/mnt/media"
        "/mnt/media/data/deluge:/config"
      ];
    };
  };
}
