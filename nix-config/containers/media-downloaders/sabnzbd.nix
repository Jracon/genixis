{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    sabnzbd = {
      hostname = "sabnzbd";
      image = "lscr.io/linuxserver/sabnzbd:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      networks = [
        "gluetun-network"
      ];
      ports = [
        "8080:8080"
      ];
      pull = "always";
      volumes = [
        "gluetun:/pia:ro"

        "/mnt/media:/mnt/media"
        "/mnt/media/data/sabnzbd:/config"
      ];
    };
  };
}
