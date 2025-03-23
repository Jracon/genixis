let
  secret_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw jade.isaiah@gmail.com";

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
  "./containers/media-servers/gamevault/db_password.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/admin_username.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/admin_password.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/igdb_client_id.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/igdb_client_secret.age".publicKeys = secret_keys;

  "./containers/vaultwarden/environment.age".publicKeys = secret_keys;
}
