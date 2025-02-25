{
  ...
}:

{
  virtualisation.oci-containers.containers = {
    jellyfin = {
      hostname = "jellyfin";
      image = "lscr.io/linuxserver/jellyfin:latest";

      # devices = [ "/dev/dri:/dev/dri" ]; # waiting for next release
      environment = {
        TZ="America/Phoenix";
      };
      extraOptions = [ "--restart=unless-stopped" "--device=/dev/dri:/dev/dri" "--pull=always" ]; # device and pull options are temporary
      ports = [ 
        "8096" 
        "8920" 
        "7359/udp" 
        "1900/udp"
      ];
      # pull = "always"; # waiting for next release
      user = "1000:1000";
      volumes = [ 
        "/mnt/media/data/jellyfin:/config" 
        "/mnt/media:/mnt/media" 
      ];
    };
  };
}