let
  secret_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHA/kJG+krANRu1zfKImsdBO+TJnAZSI11YIpsYhoWIw 32557834+Jracon@users.noreply.github.com";

  secret_keys = [ secret_key ];
in
{
  "./containers/media-downloaders/gluetun/openvpn_user.age".publicKeys = secret_keys;
  "./containers/media-downloaders/gluetun/openvpn_password.age".publicKeys = secret_keys;

  "./containers/media-managers/lidarr/api_key.age".publicKeys = secret_keys;

  "./containers/media-servers/gamevault/db_password.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/admin_username.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/admin_password.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/igdb_client_id.age".publicKeys = secret_keys;
  "./containers/media-servers/gamevault/igdb_client_secret.age".publicKeys = secret_keys;
}
