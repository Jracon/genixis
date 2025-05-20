let
  secret_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw";

  secret_keys = [ secret_key ];
in
{
  # container specific
  "./modules/containers/caddy/Caddyfile.age".publicKeys = secret_keys;
  "./modules/containers/caddy/environment.age".publicKeys = secret_keys;

  "./modules/containers/mealie/environment.age".publicKeys = secret_keys;

  "./modules/containers/media-downloaders/gluetun/environment.age".publicKeys = secret_keys;

  "./modules/containers/media-managers/lidatube/environment.age".publicKeys = secret_keys;

  "./modules/containers/media-servers/gamevault/backend_environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/gamevault/db_environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/invidious/environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/invidious/companion_environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/invidious/db_environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/romm/db_environment.age".publicKeys = secret_keys;
  "./modules/containers/media-servers/romm/environment.age".publicKeys = secret_keys;

  "./modules/containers/vaultwarden/environment.age".publicKeys = secret_keys;


  # service specific
  "./modules/services/tailscale/client_secret.age".publicKeys = secret_keys;
}
