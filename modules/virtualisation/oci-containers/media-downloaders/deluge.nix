{
  config,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  networking.firewall.allowedTCPPorts = [
    8112
  ];

  system.activationScripts.create_deluge_directories.text = ''
    mkdir -p /mnt/deluge /mnt/media/downloads/torrents/incomplete /mnt/media/downloads/torrents/complete
  '';

  virtualisation.oci-containers.containers.deluge = {
    image = "lscr.io/linuxserver/deluge:2.2.0-r1-ls364"; # https://github.com/linuxserver/docker-deluge/issues/229

    hostname = "deluge";
    pull = "newer";

    dependsOn = [
      "gluetun"
    ];
    environment = oci.mediaEnvironment config.time.timeZone;
    networks = [
      "gluetun-network"
    ];
    ports = [
      "8112:8112"
    ];
    volumes = [
      "/mnt/deluge:/config"
      "/mnt/media:/mnt/media"
      "/mnt/gluetun:/pia:ro"
    ];
  };
}
