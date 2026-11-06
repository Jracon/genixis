let
  # the trailing newline would otherwise reach agenix as an empty recipient
  readKey = file: builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile file);

  # one pair per host that consumes a system secret; the private half lives only in the system channel of that host
  hostKeys = names: map (name: readKey ./.ssh/agenix/hosts/${name}.pub) names;

  # one pair per user; it decrypts only the two user secrets, so both name every user key.
  # the key of nixos is pending: add it to this list when its public half exists (see AGENTS.md, Secrets)
  userKeys = map (name: readKey ./.ssh/agenix/users/${name}.pub) [
    "dev"
    "jademeskill"
    "root"
  ];
in
{
  ".ssh/config.age".publicKeys = userKeys;
  "modules/programs/cli/claude/zai_token.age".publicKeys = userKeys;
  "modules/services/dispatcher/webhook.age".publicKeys = hostKeys [ "services" ];
  "modules/services/tailscale/client_secret.age".publicKeys = hostKeys [
    "media"
    "services"
  ];
  "modules/virtualisation/oci-containers/caddy/environment.age".publicKeys = hostKeys [ "services" ];
  "modules/virtualisation/oci-containers/dawarich/db_environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/dawarich/environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/forgejo/genixis_runner_token.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/invidious/companion_environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/invidious/db_environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/invidious/environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/mealie/environment.age".publicKeys = hostKeys [ "services" ];
  "modules/virtualisation/oci-containers/media-downloaders/gluetun/environment.age".publicKeys =
    hostKeys
      [ "media" ];
  "modules/virtualisation/oci-containers/media-managers/recyclarr/config.age".publicKeys = hostKeys [
    "media"
  ];
  "modules/virtualisation/oci-containers/media-servers/gamevault/backend_environment.age".publicKeys =
    hostKeys
      [ "media" ];
  "modules/virtualisation/oci-containers/media-servers/gamevault/db_environment.age".publicKeys =
    hostKeys
      [ "media" ];
  "modules/virtualisation/oci-containers/media-servers/romm/db_environment.age".publicKeys =
    hostKeys
      [ "media" ];
  "modules/virtualisation/oci-containers/media-servers/romm/environment.age".publicKeys = hostKeys [
    "media"
  ];
  "modules/virtualisation/oci-containers/monica/db_environment.age".publicKeys = hostKeys [
    "services"
  ];
  "modules/virtualisation/oci-containers/monica/environment.age".publicKeys = hostKeys [ "services" ];
  "modules/virtualisation/oci-containers/radicale/config.age".publicKeys = hostKeys [ "services" ];
  "modules/virtualisation/oci-containers/radicale/users.age".publicKeys = hostKeys [ "services" ];
  "modules/virtualisation/oci-containers/vaultwarden/environment.age".publicKeys = hostKeys [
    "services"
  ];
}
