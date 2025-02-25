{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    jellyfin = {
      hostname = "jellyfin";
      image = "lscr.io/linuxserver/jellyfin:latest";

      devices = [ "/dev/dri:/dev/dri" ];
      environment = {
        TZ="America/Phoenix";
      };
      extraOptions = [ "--restart=unless-stopped" ];
      ports = [ 
        "8096" 
        "8920" 
        "7359/udp" 
        "1900/udp"
      ];
      pull = "always";
      user = "1000:1000";
      volumes = [ 
        "/mnt/media/data/jellyfin:/config" 
        "/mnt/media:/mnt/media" 
      ];
    };
  };
}