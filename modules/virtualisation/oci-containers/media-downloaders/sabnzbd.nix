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
    8080
  ];

  system.activationScripts.create_sabnzbd_directories.text = ''
    mkdir -p /mnt/sabnzbd /mnt/media/downloads/usenet/incomplete /mnt/media/downloads/usenet/complete && chown -R 1000:1000 /mnt/sabnzbd /mnt/media/downloads/usenet
  '';

  virtualisation.oci-containers.containers.sabnzbd = {
    image = "lscr.io/linuxserver/sabnzbd:latest";

    hostname = "sabnzbd";
    pull = "newer";

    environment = oci.mediaEnvironment config.time.timeZone;
    ports = [
      "8080:8080"
    ];
    volumes = [
      "/mnt/sabnzbd:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
