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
    13378
  ];

  system.activationScripts.create_audiobookshelf_directories.text = ''
    mkdir -p /mnt/audiobookshelf/config /mnt/audiobookshelf/metadata && chown ${oci.mediaUser} -R /mnt/audiobookshelf
  '';

  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:latest";

    hostname = "audiobookshelf";
    pull = "newer";
    user = oci.mediaUser;

    environment = {
      PORT = "13378";
      TZ = config.time.timeZone;
    };
    ports = [
      "13378:13378"
    ];
    volumes = [
      "/mnt/media/audiobooks:/audiobooks"
      "/mnt/audiobookshelf/config:/config"
      "/mnt/audiobookshelf/metadata:/metadata"
      "/mnt/media/podcasts:/podcasts"
    ];
  };
}
