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
    4533
  ];

  system.activationScripts.create_navidrome_directory.text = ''
    mkdir -p /mnt/navidrome && chown ${oci.mediaUser} -R /mnt/navidrome
  '';

  virtualisation.oci-containers.containers.navidrome = {
    image = "docker.io/deluan/navidrome:latest";

    hostname = "navidrome";
    pull = "newer";
    user = oci.mediaUser;

    environment = {
      TZ = config.time.timeZone;
    };
    ports = [
      "4533:4533"
    ];
    volumes = [
      "/mnt/navidrome:/data"
      "/mnt/media/music:/music"
    ];
  };
}
