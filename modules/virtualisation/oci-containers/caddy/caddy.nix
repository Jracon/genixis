{
  config,
  ...
}:

{
  age.secrets.caddy_caddyfile.file = ./Caddyfile.age;

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
    ports = [
      "80:80"
      "443:443"
      "443:443/udp"
    ];
    volumes = [
      "/mnt/caddy/config:/config"
      "/mnt/caddy/data:/data"
      "${config.age.secrets.caddy_caddyfile.path}:/etc/caddy/Caddyfile"
    ];
  };
}
