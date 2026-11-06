{
  config,
  lib,
  ...
}:

let
  # the secret exists only after the owner creates it with `agenix -e` (the
  # pattern of the dispatcher webhook). Until then the container starts with
  # the committed Caddyfile and no variables, so Caddy exits at startup and
  # names the missing variable
  environmentExists = builtins.pathExists ./environment.age;
in
{
  age.secrets = lib.mkIf environmentExists {
    caddy_environment.file = ./environment.age;
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [
      443
    ];
  };

  system.activationScripts.create_caddy_directories.text = ''
    mkdir -p /mnt/caddy/config /mnt/caddy/data
  '';

  virtualisation.oci-containers.containers.caddy = {
    image = "ghcr.io/caddybuilds/caddy-cloudflare:latest";

    hostname = "caddy";
    pull = "newer";

    capabilities = {
      NET_ADMIN = true;
    };
    environmentFiles = lib.mkIf environmentExists [
      config.age.secrets.caddy_environment.path
    ];
    ports = [
      "80:80"
      "443:443"
      "443:443/udp"
    ];
    volumes = [
      "/mnt/caddy/config:/config"
      "/mnt/caddy/data:/data"
      "${./Caddyfile}:/etc/caddy/Caddyfile"
    ];
  };
}
