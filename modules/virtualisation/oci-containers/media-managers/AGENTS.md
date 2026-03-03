# media-managers/ — Arr Stack + Media Management

Loaded as a group on the `media` NixOS host. Manages metadata, indexing, requests, and quality profiles for the media library.

## FILES

| File | Service | Notes |
|------|---------|-------|
| `radarr.nix` | Radarr | Movie management |
| `sonarr.nix` | Sonarr | TV show management |
| `bazarr.nix` | Bazarr | Subtitle management |
| `prowlarr.nix` | Prowlarr | Indexer management |
| `jellyseerr.nix` | Jellyseerr | Media request UI |
| `kapowarr.nix` | Kapowarr | Comic management |
| `calibre.nix` | Calibre | Ebook library |
| `recyclarr.nix` | Recyclarr | Syncs quality profiles to Radarr/Sonarr |
| `scripts.nix` | — | Installs `shellcheck` + `shfmt` system packages for shell script tooling |

## RECYCLARR PATTERN

Recyclarr mounts its config from an agenix secret (the YAML is sensitive — contains API keys). Secret requires custom ownership:

```nix
age.secrets.recyclarr_config = {
  file = ./recyclarr/config.age;
  group = "1000";
  mode = "400";
  owner = "1000";
};
# container also sets: user = "1000:1000";
```

Secret subdir: `./recyclarr/config.age` (not flat, uses named subdir).

## DATA LAYOUT

```
/mnt/<service>/     # each arr app gets its own config dir
/mnt/media/         # shared media library (bind-mounted read-write)
/mnt/recyclarr/configs/
```

## ANTI-PATTERNS

- Never put API keys in `environment.*` — use `environmentFiles` or secret volume mount
- `scripts.nix` is a support file, not a container — don't add container config to it
