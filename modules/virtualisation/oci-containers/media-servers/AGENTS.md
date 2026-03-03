# media-servers/ — Media Serving Stack

Loaded as a group on the `media` NixOS host.

## FILES

| File | Service | Notes |
|------|---------|-------|
| `jellyfin.nix` | Jellyfin | `--network=host`, GPU passthrough `/dev/dri`, PUID/PGID=1000, daily playlist timer |
| `kavita.nix` | Kavita | Comic/manga/book reader |
| `syncthing.nix` | Syncthing | File sync |
| `gamevault.nix` | GameVault + postgres | Isolated `gamevault-network`; 2 agenix secrets |
| `romm.nix` | RomM + mariadb | Isolated `romm-network`; config.yaml committed at `./romm/config.yaml` |
| `pool.nix` | ZFS pool config | **Not a container** — sets kernel, imports `media` ZFS pool, enables autoScrub |

## UNIQUE PATTERNS

**pool.nix** — Only non-container file in this dir. Sets `boot.kernelPackages` to latest ZFS-compatible kernel using `lib.filterAttrs` + `lib.sort`. Include whenever a ZFS media pool is needed.

**Jellyfin** uses `--network=host` via `extraOptions` (not the `networks` attr) — necessary for mDNS/DLNA discovery. Firewall rules still required.

**Multi-container services** (gamevault, romm): each gets an isolated podman network created in `activationScripts`. DB container has no exposed ports — only app container talks to host.

**Committed config** (romm): `./romm/config.yaml` is committed and bind-mounted into the container. Not encrypted — contains only non-secret settings.

## DATA LAYOUT

```
/mnt/jellyfin/          # jellyfin config
/mnt/media/             # shared media root (bind-mounted into jellyfin, arr stack)
/mnt/media/games/       # romm library
/mnt/romm/assets|config/
/mnt/gamevault/
```

## ANTI-PATTERNS

- Never use `extraOptions = ["--network=host"]` except for Jellyfin (DLNA requirement)
- Never expose DB container ports to host — keep DB on isolated network only
- Never omit `dependsOn` when app container requires DB to be up first
