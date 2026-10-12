{
  networking.firewall.allowedTCPPorts = [
    13378
  ];

  system.activationScripts.create_audiobookshelf_directories.text = ''
    mkdir -p /mnt/audiobookshelf/config /mnt/audiobookshelf/metadata && chown 1000:1000 -R /mnt/audiobookshelf
  '';

  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:latest";

    hostname = "audiobookshelf";
    pull = "newer";
    user = "1000:1000";

    environment = {
      PORT = "13378";
      TZ = "America/Phoenix";
    };
    ports = [
      "13378:13378"
    ];
    volumes = [
      "/mnt/audiobookshelf/config:/config"
      "/mnt/audiobookshelf/metadata:/metadata"
      "/mnt/media/audiobooks:/audiobooks"
      "/mnt/media/podcasts:/podcasts"
    ];
  };
}
