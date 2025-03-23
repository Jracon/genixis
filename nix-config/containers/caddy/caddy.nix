{
  ...
}:

{
  age.secrets = {
    caddy_caddyfile.file = ./Caddyfile.age;
    caddy_cloudflare_api_token.file = ./cloudflare_api_token.age;
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

  virtualisation.oci-containers.containers = {
    caddy = {
      hostname = "caddy";
      image = "ghcr.io/caddybuilds/caddy-cloudflare:latest";

      capabilities = {
        NET_ADMIN = true;
      };
      environment = {
        CLOUDFLARE_API_TOKEN = config.age.secrets.caddy_cloudflare_api_token.path;
      };
      ports = [
        "80:80"
        "443:443"
        "443:443/udp"
      ];
      pull = "always";
      volumes = [
        "${config.age.secrets.caddy_caddyfile.path}:/etc/caddy/Caddyfile"
        "/mnt/caddy/data:/data"
        "caddy_config:/config"
      ];
    };
  };
}
