let
  # the trailing newline would otherwise reach agenix as an empty recipient
  secret_keys = [
    (builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile ./.ssh/genixis_secrets.pub))
  ];
in
{
  ".ssh/config.age".publicKeys = secret_keys;
  "modules/programs/cli/claude/zai_token.age".publicKeys = secret_keys;
  "modules/services/tailscale/client_secret.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/caddy/Caddyfile.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/forgejo/genixis_runner_token.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/invidious/companion_environment.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/invidious/db_environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/invidious/environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/mealie/environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/media-downloaders/gluetun/environment.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/media-managers/recyclarr/config.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/media-servers/gamevault/backend_environment.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/media-servers/gamevault/db_environment.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/media-servers/romm/db_environment.age".publicKeys =
    secret_keys;
  "modules/virtualisation/oci-containers/media-servers/romm/environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/monica/db_environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/monica/environment.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/radicale/config.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/radicale/users.age".publicKeys = secret_keys;
  "modules/virtualisation/oci-containers/vaultwarden/environment.age".publicKeys = secret_keys;
}
