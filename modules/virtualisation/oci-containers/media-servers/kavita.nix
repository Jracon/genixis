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
    5000
  ];

  system.activationScripts.create_kavita_directories.text = ''
    mkdir -p /mnt/kavita
  '';

  virtualisation.oci-containers.containers.kavita = {
    image = "lscr.io/linuxserver/kavita:latest";

    hostname = "kavita";
    pull = "newer";

    environment = oci.mediaEnvironment config.time.timeZone;
    ports = [
      "5000:5000"
    ];
    volumes = [
      "/mnt/kavita:/config"
      "/mnt/media:/mnt/media"
    ];
  };
}
