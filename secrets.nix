let
  secret_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw"
  ];
in
{
  "./modules/services/tailscale/client_secret.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/caddy/Caddyfile.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/invidious/companion_environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/invidious/db_environment.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/invidious/environment.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/mealie/environment.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/media-downloaders/gluetun/environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/media-managers/recyclarr/config.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/media-servers/gamevault/backend_environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/media-servers/gamevault/db_environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/media-servers/romm/db_environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/media-servers/romm/environment.age".publicKeys =
    secret_keys;
  "./modules/virtualisation/oci-containers/monica/db_environment.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/monica/environment.age".publicKeys = secret_keys;
  "./modules/virtualisation/oci-containers/vaultwarden/environment.age".publicKeys = secret_keys;
}
