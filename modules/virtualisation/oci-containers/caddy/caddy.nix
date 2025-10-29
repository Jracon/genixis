{
  config,
  ...
}:

{
  age.secrets = {
    caddy_caddyfile.file = ./Caddyfile.age;
    caddy_environment = {
      file = ./environment.age;
      # mode = "600";
    };
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

  system.activationScripts.create_caddy_directory.text = ''
    mkdir -p /mnt/caddy/data
  '';

  virtualisation.oci-containers.containers.caddy = {
    image = "ghcr.io/caddybuilds/caddy-cloudflare:latest";

    hostname = "caddy";
    pull = "newer";

    capabilities = {
      NET_ADMIN = true;
    };
    environmentFiles = [
      config.age.secrets.caddy_environment.path
    ];
    ports = [
      "80:80"
      "443:443"
      "443:443/udp"
    ];
    volumes = [
      "caddy_config:/config"
      "/mnt/caddy/data:/data"
      "${config.age.secrets.caddy_caddyfile.path}:/etc/caddy/Caddyfile"
    ];
  };
}
