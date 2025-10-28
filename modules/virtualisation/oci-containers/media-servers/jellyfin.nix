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
      1900
      7359
    ];
  };

  system.activationScripts.create_jellyfin_directory.text = ''
    mkdir -p /mnt/jellyfin
  '';

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    pull = "always";
    hostname = "jellyfin";

    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/Phoenix";
    };

    volumes = [
      "/mnt/jellyfin:/config"
      "/mnt/media:/mnt/media"
    ];

    devices = [
      "/dev/dri:/dev/dri"
    ];

    ports = [
      "1900:1900/udp"
      "7359:7359/udp"
      "8096:8096"
      "8920:8920"
    ];
  };
}
