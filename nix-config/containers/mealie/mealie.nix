{
  ...
}:

{
  age.secrets = {
    mealie_base_url.file = ./base_url.age;
    mealie_smtp_host.file = ./smtp_host.age;
    mealie_smtp_port.file = ./smtp_port.age;
    mealie_smtp_auth_strategy.file = ./smtp_auth_strategy.age;
    mealie_smtp_from_email.file = ./smtp_from_email.age;
    mealie_smtp_user.file = ./smtp_user.age;
    mealie_smtp_password.file = ./smtp_password.age;
    mealie_openai_api_key.file = ./openai_api_key.age;
  };

  networking.firewall = {
    allowedTCPPorts = [
      9925
    ]
  };

  virtualisation.oci-containers.containers = {
    mealie = {
      hostname = "caddy";
      image = "ghcr.io/mealie-recipes/mealie:2.8.0";

      environment = {
        ALLOW_SIGNUP = "true";
        PUID = "1000";
        PGID = "1000";
        TZ = "America/Phoenix";
        BASE_URL = config.age.secrets.mealie_base_url.path;
        SMTP_HOST = config.age.secrets.mealie_smtp_host.path;
        SMTP_PORT = config.age.secrets.mealie_smtp_port.path;
        SMTP_AUTH_STRATEGY = config.age.secrets.mealie_smtp_auth_strategy.path;
        SMTP_FROM_EMAIL = config.age.secrets.mealie_smtp_from_email.path;
        SMTP_USER = config.age.secrets.mealie_smtp_user.path;
        SMTP_PASSWORD = config.age.secrets.mealie_smtp_password.path;
        OPENAI_API_KEY = config.age.secrets.mealie_openai_api_key.path;
      };
      ports = [
        "9925:9000"
      ];
      pull = "always";
      volumes = [
        "/mnt/mealie:/app/data"
      ];
    };
  };
}
