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
    8181
  ];

  system.activationScripts.create_calibre_directories.text = ''
    mkdir -p /mnt/calibre /mnt/media/data/calibre-library && chown -R 1000:1000 /mnt/calibre /mnt/media/data/calibre-library
  '';

  virtualisation.oci-containers.containers.calibre = {
    image = "lscr.io/linuxserver/calibre:latest";

    hostname = "calibre";
    pull = "newer";

    environment = oci.mediaEnvironment config.time.timeZone;
    ports = [
      "8081:8080"
      "8082:8081"
      "8181:8181"
    ];
    volumes = [
      "/mnt/media/data/calibre-library:/calibre-library"
      "/mnt/calibre:/config"
      "/mnt/media/downloads/shelfmark:/cwa-book-ingest"
      "/mnt/media/books:/mnt/media/books"
    ];
  };
}
