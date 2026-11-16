{
  config,
  pkgs,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  age.secrets.gluetun_environment.file = ./gluetun/environment.age;

  system.activationScripts = {
    create_gluetun_directory.text = ''
      mkdir -p /mnt/gluetun
    '';
    create_gluetun-network.text = oci.networkCreate pkgs.podman "gluetun";
  };

  virtualisation.oci-containers.containers.gluetun = {
    image = "ghcr.io/qdm12/gluetun";

    hostname = "gluetun";
    pull = "newer";

    capabilities = {
      NET_ADMIN = true;
    };
    devices = [
      "/dev/net/tun:/dev/net/tun"
    ];
    environmentFiles = [
      config.age.secrets.gluetun_environment.path
    ];
    volumes = [
      "/mnt/gluetun:/gluetun"
    ];
  };
}
