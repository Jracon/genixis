# oci-containers/ — Self-Hosted Services

Podman OCI container definitions grouped by function. Each subdirectory is a loadable module group in `flake.nix`.

## GROUPS

| Dir | Services | Host |
|-----|----------|------|
| `media-downloaders/` | Deluge (torrent), SABnzbd (usenet), Shelfmark, Gluetun (VPN) | `media` |
| `media-managers/` | Radarr, Sonarr, Bazarr, Prowlarr, Jellyseerr, Kapowarr, Recyclarr, Calibre | `media` |
| `media-servers/` | Jellyfin, Kavita, GameVault, RomM, Syncthing, Pool (ZFS) | `media` |
| `caddy/` | Reverse proxy (cloudflare DNS plugin) | `services` |
| `forgejo/` | Self-hosted git + Forgejo Actions runner | `services` |
| `invidious/` | YouTube frontend + companion + postgres | `services` |
| `mealie/` | Recipe manager | `services` |
| `monica/` | Personal CRM + postgres | `services` |
| `vaultwarden/` | Bitwarden-compatible password manager | `services` |
| `languagetool.nix` | Grammar checker (flat file, no subdir) | `services` |

## STANDARD CONTAINER PATTERN

```nix
{ config, pkgs, ... }:
{
  age.secrets.my_secret.file = ./secret.age;        # if secrets needed

  networking.firewall.allowedTCPPorts = [ 8080 ];    # ALWAYS add firewall rules

  system.activationScripts.create_my-service_directory.text = ''
    mkdir -p /mnt/my-service
  '';

  virtualisation.oci-containers.containers.my-service = {
    image = "repo/image:tag";
    hostname = "my-service";
    pull = "newer";                                   # always "newer", never "always"
    environmentFiles = [ config.age.secrets.my_secret.path ];
    ports = [ "8080:80" ];
    volumes = [ "/mnt/my-service:/data" ];
    environment.TZ = "America/Phoenix";
  };
}
```

## MULTI-CONTAINER PATTERN (isolated network)

When a service has a sidecar DB or companion:
```nix
system.activationScripts.create_foo-network.text = ''
  ${pkgs.podman}/bin/podman network create foo-network --ignore
'';
# containers use: networks = [ "foo-network" ]; dependsOn = [ "foo-db" ];
```
Examples: invidious (3 containers), romm (+ mariadb), monica (+ db), gamevault (+ postgres).

## SECRET PATTERNS

- `environmentFiles` — inject env vars (most common)
- Volume-mount secret file — inject config file: `"${config.age.secrets.foo.path}:/etc/service/config"`
- Secret with custom owner/mode — recyclarr sets `group`, `mode`, `owner` on the secret attr

## ACTIVATION SCRIPT NAMING

Convention: `create_<service>_directory` or `create_<service>-network`. Use underscores in the attr name, hyphens in the network name.

## ANTI-PATTERNS

- Never `pull = "always"` — use `pull = "newer"`
- Never skip `networking.firewall` rules for exposed ports
- Never store secrets in `environment.*` — use `environmentFiles` or volume-mounted `.age` files
- Never put multi-service orchestration state in a flat `.nix` — give it a subdirectory
- Data dirs always at `/mnt/<service>/`; media always at `/mnt/media/`

## DEBUGGING

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks created
```
