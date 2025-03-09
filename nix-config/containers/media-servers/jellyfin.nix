{
  ...
}:

{
  networking.firewall = {
    allowedTCPPorts = [ 
      8096 
      8920 
    ];
    allowedUDPPorts = [ 
      8096 
      8920 
      7359 
      1900 
    ];
  };

  virtualisation.oci-containers.containers = {
    jellyfin = {
      hostname = "jellyfin";
      image = "lscr.io/linuxserver/jellyfin:latest";
      
      devices = [ 
        "/dev/dri:/dev/dri" 
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
      };
      ports = [ 
        "8096:8096" 
        "8920:8920" 
        "7359:7359/udp" 
        "1900:1900/udp"
      ];
      pull = "always";
      volumes = [ 
        "/mnt/media/data/jellyfin:/config" 
        "/mnt/media:/mnt/media" 
      ];
    };
  };
}