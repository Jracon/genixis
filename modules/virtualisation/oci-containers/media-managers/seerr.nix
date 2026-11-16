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
    5055
  ];

  system.activationScripts.create_seerr_directory.text = ''
    mkdir -p /mnt/seerr && chown ${oci.mediaUser} -R /mnt/seerr
  '';

  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:latest";

    hostname = "seerr";
    pull = "newer";

    environment = {
      TZ = config.time.timeZone;
    };
    ports = [
      "5055:5055"
    ];
    volumes = [
      "/mnt/seerr:/app/config"
    ];
  };
}
