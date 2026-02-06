# oci-containers/ - Containerized Services

OCI container definitions for self-hosted services (media, productivity, development).

---

## Structure

```
oci-containers/
├── caddy/                     # Reverse proxy & SSL
├── invidious/                 # YouTube frontend
├── languagetool.nix           # Grammar checker (single file)
├── mealie/                    # Recipe manager
├── media-downloaders/          # Download managers
│   ├── deluge.nix
│   ├── gluetun/              # VPN tunnel
│   └── shelfmark.nix
├── media-managers/            # Media organization (9 services)
│   ├── bazarr.nix
│   ├── calibre.nix
│   ├── jellyseerr.nix
│   ├── kapowarr.nix
│   ├── prowlarr.nix
│   ├── radarr.nix
│   ├── recyclarr/             # Sync tool
│   ├── scripts.nix           # Shared scripts
│   └── sonarr.nix
├── media-servers/            # Media hosting (6 services)
│   ├── gamevault.nix
│   ├── jellyfin.nix
│   ├── kavita.nix
│   ├── pool.nix
│   ├── romm/
│   └── syncthing.nix
├── monica/                   # CRM
└── vaultwarden/              # Password manager
```

---

## Where to Look

| Task                | Location                                | Notes                           |
| ------------------- | --------------------------------------- | ------------------------------- |
| Add media service   | `media-{downloaders,managers,servers}/` | Choose appropriate subdirectory |
| Add general service | `*/`                                    | Create new subdirectory         |
| Modify container    | `{service}/{service}.nix`               | Direct edit                     |
| Shared scripts      | `media-managers/scripts.nix`            | Reusable shell scripts          |
| VPN config          | `media-downloaders/gluetun/`            | Network isolation               |

---

## Patterns

### Standard Container

```nix
{
  networking.firewall.allowedTCPPorts = [ 8080 ];

  system.activationScripts.create_service_dirs.text = ''
    mkdir -p /mnt/service
  '';

  virtualisation.oci-containers.containers.my-service = {
    image = "dockerhub/image:latest";
    hostname = "my-service";
    pull = "newer";

    environment = {
      TZ = "America/Phoenix";
      PUID = "1000";
      PGID = "1000";
    };

    ports = [ "8080:80" ];
    volumes = [ "/mnt/service:/data" ];
  };
}
```

### Container with Secrets

```nix
{
  virtualisation.oci-containers.containers.vaultwarden = {
    image = "vaultwarden/server:latest";
    environmentFiles = [ config.age.secrets.vaultwarden.path ];
    # ... other config
  };
}
```

### Multiple Instances

```nix
{
  virtualisation.oci-containers.containers = {
    service-main = { /* config */ };
    service-secondary = { /* config */ };
  };
}
```

---

## Anti-Patterns

- **Hardcoded paths**: Use `/mnt/{service}` convention consistently
- **Missing firewall rules**: Always open required ports
- **Skipping activation scripts**: Create directories before containers start
- **Forgetting pull policy**: Use `pull = "newer"` for updates
