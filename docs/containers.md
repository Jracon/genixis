# The containers

The Podman container patterns and the per-service quirks of `modules/virtualisation/oci-containers/`.

## `modules/virtualisation/oci-containers/`

Podman containers are grouped by function, with one subdirectory for each group. To wire a group into `nixosConfigurations`, list its directory (or a flat file) in the module list of the host in `flake.nix`.

The directory names match their services 1:1. Run `ls` on a group to see its services. These groups load on these hosts:

- `media`: `media-downloaders/`, `media-managers/`, `media-servers/`.
- `services`: `agentsview/`, `caddy/`, `continuwuity/`, `dawarich/`, `forgejo/`, `invidious/`, `mealie/`, `monica/`, `radicale/`, `vaultwarden/`, and the flat file `languagetool.nix`.

### Standard container pattern

```nix
{
  config,
  ...
}:

{
  age.secrets.my_secret.file = ./secret.age; # if secrets needed

  # ALWAYS add firewall rules
  networking.firewall.allowedTCPPorts = [
    8080
  ];

  system.activationScripts.create_my-service_directory.text = ''
    mkdir -p /mnt/my-service
  '';

  virtualisation.oci-containers.containers.my-service = {
    image = "repo/image:tag";

    hostname = "my-service";
    pull = "newer"; # always "newer", never "always"

    environment = {
      TZ = "America/Phoenix";
    };
    environmentFiles = [
      config.age.secrets.my_secret.path
    ];
    ports = [
      "8080:80"
    ];
    volumes = [
      "/mnt/my-service:/data"
    ];
  };
}
```

Persistent data is always a bind mount under `/mnt/<service>/`. When a service has several mounts, use one subdirectory for each mount (for example `/mnt/romm/mysql` and `/mnt/romm/redis-data`). **Do not use named Podman volumes.** Create every bind-mount directory in the activation script.

### Multi-container pattern (isolated network)

Use this pattern when a service has a sidecar DB or companion:

```nix
system.activationScripts.create_foo-network.text = ''
  ${pkgs.podman}/bin/podman network create foo-network --ignore
'';
# Then in each container: networks = [ "foo-network" ]; dependsOn = [ "foo-db" ];
```

Examples: invidious (3 containers), romm (+ mariadb), monica (+ db), gamevault (+ postgres), dawarich (+ postgis and redis).

### VPN routing pattern (media-downloaders)

Gluetun is the VPN gateway. Deluge joins `gluetun-network` and depends on it. Its traffic is verified to exit through the VPN.

```nix
virtualisation.oci-containers.containers.my-downloader = {
  dependsOn = [ "gluetun" ];
  networks = [ "gluetun-network" ];
  # ...
};
```

Torrent clients must route through gluetun. `sabnzbd` (Usenet, TLS) and `shelfmark` currently do **not** join `gluetun-network`.

The secret of gluetun is at `./gluetun/environment.age`. It is in a subdirectory, not flat. The state of gluetun is at `/mnt/gluetun`. Deluge also mounts this directory read-only at `/pia` for the forwarded port.

### Secret patterns

- `environmentFiles` injects environment variables. This is the most common pattern.
- A volume-mounted secret file injects a config file: `"${config.age.secrets.foo.path}:/etc/service/config"`.
- Custom ownership: set `group`, `mode`, and `owner` on the secret attribute to match a container user that is not root. Recyclarr and Radicale do this.

### Notable per-service quirks

- **Jellyfin** uses `extraOptions = ["--network=host"]` (not `networks`). It needs this for mDNS/DLNA discovery. It is the only container that should do this. It still needs firewall rules.
- **pool.nix** (media-servers) is the one non-container file in that directory. It sets `boot.kernelPackages` for ZFS compatibility. It imports the `media` ZFS pool with autoScrub. It also sets a default `networking.hostId`, because ZFS demands one. The real machine sets its own value in its machine-local configuration, and a plain value wins over the default. So the rebuild of `media` keeps its own hostId, and a local `nix flake check --impure` on a machine without a hostId still passes.
- **romm** commits `./romm/config.yaml` directly. The container bind-mounts it. It is not a secret and has no sensitive values. The `mariadb:latest` tag of romm follows the example compose file of upstream, on purpose.
- **recyclarr** mounts its config from an agenix secret (`./recyclarr/config.age`, which holds API keys). It runs as `user = "1000:1000"` to match the ownership of the secret.
- **caddy** mounts the committed `./caddy/Caddyfile` at `/etc/caddy/Caddyfile`. The file holds the routing table in plaintext. It reads four variables from the environment: `CF_API_TOKEN`, `HA_IP`, `MEDIA_IP`, and `SERVICES_IP`. The secret `./caddy/environment.age` holds the values, and `environmentFiles` feeds them to the container. Create the secret with `agenix -e`, then run `git add` on it. Do this before the next rebuild of `services`. If a variable is not set, Caddy exits at startup and names the variable.
- **invidious** copies SQL and init scripts from the pinned `invidious` flake input (`flake = false`). NixOS specialArgs pass the input. Update it with `nix flake update invidious`.
- **forgejo.nix** also runs the native `services.forgejo-runner` instance that executes the CI of this repository.
  - Its only label is `native:host`. Jobs run directly on `services` as the DynamicUser of the runner. They build through the sandboxed nix-daemon of the host.
  - A `docker://` label would add the runner to the rootful `podman` group. Builds in a job container run unsandboxed.
  - Put the tools that a job needs in its `hostPackages`.
- **dawarich** runs Sidekiq inside the app container, through `SIDEKIQ_EMBEDDED = "true"`. The entrypoint of the image creates the database, runs the migrations, and seeds the data at each start. The module sets the `entrypoint` option, because the image starts with `bundle exec`. The web port is 3001, because invidious uses 3000. Add the route for Dawarich in the committed `caddy/Caddyfile`.
- **agentsview** is the audit read layer of the factory loop (issue #74 phase 4). The image tag is pinned to an exact version; upgrade it deliberately, because the archive schema migrates often.
  - It binds to loopback only (`127.0.0.1:8790`) and opens **no** firewall port. Reach it through an ssh port forward: `ssh -L 8790:127.0.0.1:8790 dev@services`. This is deliberate, like the tailnet-only stance of `rclone-webdav`.
  - The session directories of `dev` are read-only binds. The container reads and labels only. It never launches a session: the image holds no harness binary, and the binds are read-only.
  - It needs no secret of this repository. It generates its own bearer token into `/mnt/agentsview/config.toml` on first start. Read the token there.
  - The dispatcher does not depend on it. When the container is lost, the loop keeps working and only the audit degrades.
  - Telemetry stays off (`AGENTSVIEW_TELEMETRY_ENABLED = "0"`). Semantic search is off, because it is opt-in upstream.

### Activation script naming

Use `create_<service>_directory` or `create_<service>_directories` for directories. Use `create_<service>-network` for networks. The attribute name has underscores. The network name has hyphens. Always assign to `.text`.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```
