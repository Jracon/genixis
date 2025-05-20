{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets.gluetun_environment = {
    file = ./gluetun/environment.age;
    # mode = "600";
  };

  networking.firewall.allowedTCPPorts = [
    8080
    8112
  ];

  system.activationScripts.create_gluetun-network.text = ''
    ${pkgs.podman}/bin/podman network create gluetun-network --ignore
  '';

  virtualisation.oci-containers.containers.gluetun = {
    image = "ghcr.io/qdm12/gluetun";
    pull = "newer";
    hostname = "gluetun";

    capabilities = {
      NET_ADMIN = true;
    };

    environmentFiles = [
      config.age.secrets.gluetun_environment.path
    ];

    volumes = [
      "gluetun:/gluetun"
    ];

    devices = [
      "/dev/net/tun:/dev/net/tun"
    ];
  };
}
