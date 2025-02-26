{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [ 8097 8920 ];
    allowedUDPPorts = [ 8097 8920 7359 1900 ];
  };

  virtualisation.oci-containers.containers = {
    jellyfin = {
      hostname = "jellyfin";
      image = "jellyfin/jellyfin";

      devices = [ "/dev/dri:/dev/dri" ];
      environment = {
        TZ="America/Phoenix";
      };
      ports = [ 
        "8097" 
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