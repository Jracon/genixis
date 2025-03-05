{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    lidarr = {
      hostname = "lidarr";
      image = "lscr.io/linuxserver/lidarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [ "8686" ];
      pull = "always";
      volumes = [
        "/mnt/media/data/lidarr:/config"
        "/mnt/media:/mnt/media"
      ];
    };
    
    lidatube = {
      hostname = "lidatube";
      image = "thewicklowwolf/lidatube:latest";

      environment = {
        lidarr_address = "http://127.0.0.1:8686";
        lidarr_api_key = "API KEY";
        preferred_codec = "flac";
        sync_schedule = "3,9,15,21";
      };
      ports = [ "5001:5000" ];
      pull = "always";
      volumes = [
        "/mnt/media/data/lidatube:/lidatube/config"
        "/mnt/media/music:/lidatube/downloads"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };
  };
}