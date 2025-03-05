{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    sonarr = {
      hostname = "sonarr";
      image = "lscr.io/linuxserver/sonarr:latest";

      environment = {
        PUID = 1000;
        PGID = 1000;
        TZ = America/Phoenix;
      };
      ports = [ "8989" ];
      pull = "always";
      volumes = [
        "/mnt/media/data/sonarr:/config"
        "/mnt/media:/mnt/media"
      ];
    };
    
    sonarr-anime = {
      hostname = "sonarr-anime";
      image = "lscr.io/linuxserver/sonarr:latest";

      environment = {
        PUID = 1000;
        PGID = 1000;
        TZ = America/Phoenix;
      };
      ports = [ "8990:8989" ];
      pull = "always";
      volumes = [
        "/mnt/media/data/sonarr-anime:/config"
        "/mnt/media:/mnt/media"
      ];
    };
  };
}