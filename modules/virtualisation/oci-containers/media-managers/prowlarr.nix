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
    9696
  ];

  system.activationScripts.create_prowlarr_directory.text = ''
    mkdir -p /mnt/prowlarr
  '';

  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:latest";

    hostname = "prowlarr";
    pull = "newer";

    environment = oci.mediaEnvironment config.time.timeZone;
    ports = [
      "9696:9696"
    ];
    volumes = [
      "/mnt/prowlarr:/config"
    ];
  };
}
