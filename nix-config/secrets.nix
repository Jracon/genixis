let
  secret_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw";

  secret_keys = [ secret_key ];
in
{
  "./containers/caddy/Caddyfile.age".publicKeys = secret_keys;
  "./containers/caddy/environment.age".publicKeys = secret_keys;

  "./containers/mealie/environment.age".publicKeys = secret_keys;

  "./containers/media-downloaders/gluetun/environment.age".publicKeys = secret_keys;

  "./containers/media-managers/lidatube/environment.age".publicKeys = secret_keys;

  "./containers/media-servers/gamevault/backend_environment.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/db_environment.age".publicKeys = secret_keys;

  "./containers/media-servers/romm/environment.age".publicKeys = secret_keys;
  "./containers/media-servers/romm/db_environment.age".publicKeys = secret_keys;

  "./containers/vaultwarden/environment.age".publicKeys = secret_keys;
}
