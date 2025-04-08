{
  config, 
  pkgs, 
  ...
}:

{
  age.secrets = {
    gluetun_environment = {
      file = ./gluetun/environment.age;
      mode = "600";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      8080
      8112
    ];
  };

  system.activationScripts = {
    create_gluetun-network.text = ''
      ${pkgs.podman}/bin/podman network create gluetun-network --ignore
    '';
  };

  virtualisation.oci-containers.containers = {
    gluetun = {
      hostname = "gluetun";
      image = "ghcr.io/qdm12/gluetun";

      capabilities = {
        NET_ADMIN = true;
      };
      devices = [
        "/dev/net/tun:/dev/net/tun"
      ];
      environmentFiles = [
        config.age.secrets.gluetun_environment.path
      ];
      # ports = [
      #   "8080:8080"
      #   "8112:8112"
      # ];
      pull = "always";
      volumes = [
        "gluetun:/gluetun"
      ];
    };
  };
}
