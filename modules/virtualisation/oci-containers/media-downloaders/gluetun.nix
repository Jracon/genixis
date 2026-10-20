{
  config,
  pkgs,
  ...
}:

{
  age.secrets.gluetun_environment.file = ./gluetun/environment.age;

  system.activationScripts = {
    create_gluetun_directory.text = ''
      mkdir -p /mnt/gluetun
    '';
    create_gluetun-network.text = ''
      ${pkgs.podman}/bin/podman network create gluetun-network --ignore
    '';
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
