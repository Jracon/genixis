{
  config, 
  ...
}:

{
  age.secrets = {
    caddy_caddyfile.file = ./Caddyfile.age;
    caddy_environment = {
      file = ./environment.age;
      mode = "600";
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

  system.activationScripts = {
    create_caddy_directory.text = ''
      mkdir -p /mnt/caddy/data
    '';
  };

  virtualisation.oci-containers.containers = {
    caddy = {
      hostname = "caddy";
      image = "ghcr.io/caddybuilds/caddy-cloudflare:latest";

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
      pull = "always";
      volumes = [
        "${config.age.secrets.caddy_caddyfile.path}:/etc/caddy/Caddyfile"
        "/mnt/caddy/data:/data"
        "caddy_config:/config"
      ];
    };
  };
}
