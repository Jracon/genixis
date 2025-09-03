let
  secret_keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw"
  ];
in
  {
    "./modules/containers/caddy/Caddyfile.age".publicKeys = secret_keys;
    "./modules/containers/caddy/environment.age".publicKeys = secret_keys;
    "./modules/containers/invidious/companion_environment.age".publicKeys = secret_keys;
    "./modules/containers/invidious/db_environment.age".publicKeys = secret_keys;
    "./modules/containers/invidious/environment.age".publicKeys = secret_keys;
    "./modules/containers/mealie/environment.age".publicKeys = secret_keys;
    "./modules/containers/media-downloaders/gluetun/environment.age".publicKeys = secret_keys;
    "./modules/containers/media-managers/lidatube/environment.age".publicKeys = secret_keys;
    "./modules/containers/media-servers/gamevault/backend_environment.age".publicKeys = secret_keys;
    "./modules/containers/media-servers/gamevault/db_environment.age".publicKeys = secret_keys;
    "./modules/containers/media-servers/romm/db_environment.age".publicKeys = secret_keys;
    "./modules/containers/media-servers/romm/environment.age".publicKeys = secret_keys;
    "./modules/containers/monica/environment.age".publicKeys = secret_keys;
    "./modules/containers/monica/db_environment.age".publicKeys = secret_keys;
    "./modules/containers/vaultwarden/environment.age".publicKeys = secret_keys;
    "./modules/services/tailscale/client_secret.age".publicKeys = secret_keys;
  }
