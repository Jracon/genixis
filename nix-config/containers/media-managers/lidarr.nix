{
  ...
}:

{
  age.secrets = {
    lidarr_api_key.file = ./lidarr/api_key.age;
  };

  networking.firewall = {
    allowedTCPPorts = [
      5001
      8686
    ];
    allowedUDPPorts = [
      5001
      8686
    ];
  };

  virtualisation.oci-containers.containers = {
    lidarr = {
      hostname = "lidarr";
      image = "lscr.io/linuxserver/lidarr:latest";

      environment = {
        PUID = "1000";
        PGID = "1000";

        TZ = "America/Phoenix";
      };
      ports = [
        "8686:8686"
      ];
      pull = "always";
      volumes = [
        "/mnt/media:/mnt/media"
        "/mnt/media/data/lidarr:/config"
      ];
    };

    lidatube = {
      hostname = "lidatube";
      image = "thewicklowwolf/lidatube:latest";

      environment = {
        lidarr_address = "http://127.0.0.1:8686";
        lidarr_api_key = config.age.secrets.lidarr_api_key.path;
        preferred_codec = "flac";
        sync_schedule = "3,9,15,21";
      };
      ports = [
        "5001:5000"
      ];
      pull = "always";
      volumes = [
        "/etc/localtime:/etc/localtime:ro"

        "/mnt/media/data/lidatube:/lidatube/config"
        "/mnt/media/music:/lidatube/downloads"
      ];
    };
  };
}
