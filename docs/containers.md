# The containers

The Podman container patterns and the per-service quirks of `modules/virtualisation/oci-containers/`.

## `modules/virtualisation/oci-containers/`

Podman containers are grouped by function, with one subdirectory for each group. To wire a group into `nixosConfigurations`, list its directory (or a flat file) in the module list of the host in `flake.nix`.

The directory names match their services 1:1. Run `ls` on a group to see its services. These groups load on these hosts:

- `media`: `media-downloaders/`, `media-managers/`, `media-servers/`.
- `services`: `agentsview/`, `caddy/`, `continuwuity/`, `dawarich/`, `forgejo/`, `invidious/`, `mealie/`, `monica/`, `radicale/`, `vaultwarden/`, `wger/`, and the flat file `languagetool.nix`.

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

Examples: invidious (3 containers), romm (+ mariadb), monica (+ db), gamevault (+ postgres), dawarich (+ postgis and redis), wger (+ postgres, redis, nginx, and two celery containers).

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

- **Jellyfin** uses `extraOptions = ["--network=host"]` (not `networks`). It needs this for mDNS/DLNA discovery. Do not set `--network=host` on another container. It still needs firewall rules.
- **pool.nix** (media-servers) is the one non-container file in that directory. It sets `boot.kernelPackages` for ZFS compatibility. It imports the `media` ZFS pool with autoScrub. It also sets a default `networking.hostId`, because ZFS demands one. The real machine sets its own value in its machine-local configuration, and a plain value wins over the default. So the rebuild of `media` keeps its own hostId, and a local `nix flake check --impure` on a machine without a hostId still passes.
- **romm** commits `./romm/config.yaml` directly. The container bind-mounts it. It is not a secret and has no sensitive values. The `mariadb:latest` tag of romm follows the example compose file of upstream, on purpose.
- **recyclarr** mounts its config from an agenix secret (`./recyclarr/config.age`, which holds API keys). It runs as `user = "1000:1000"` to match the ownership of the secret.
- **caddy** mounts the committed `./caddy/Caddyfile` at `/etc/caddy/Caddyfile`. The file holds the routing table in plaintext. It reads four variables from the environment: `CF_API_TOKEN`, `HA_IP`, `MEDIA_IP`, and `SERVICES_IP`. The secret `./caddy/environment.age` holds the values, and `environmentFiles` feeds them to the container. Create the secret with `agenix -e`, then run `git add` on it. Do this before the next rebuild of `services`. If a variable is not set, it expands to an empty value before Caddy parses the file. The outcome of an empty value is unverified.
- **invidious** copies SQL and init scripts from the pinned `invidious` flake input (`flake = false`). NixOS specialArgs pass the input. Update it with `nix flake update invidious`.
- **forgejo.nix** also runs the native `services.forgejo-runner` instance that executes the CI of this repository.
  - Its only label is `native:host`. Jobs run directly on `services` as the DynamicUser of the runner. They build through the sandboxed nix-daemon of the host.
  - A `docker://` label would add the runner to the rootful `podman` group. Builds in a job container run unsandboxed.
  - Put the tools that a job needs in its `hostPackages`.
- **dawarich** runs Sidekiq inside the app container, through `SIDEKIQ_EMBEDDED = "true"`. The entrypoint of the image creates the database, runs the migrations, and seeds the data at each start. The module sets the `entrypoint` option, because the image starts with `bundle exec`. The web port is 3001, because invidious uses 3000. Add the route for Dawarich in the committed `caddy/Caddyfile`.
- **agentsview** is the audit read layer of the factory loop (issue #74 phase 4). The module pins the image tag to an exact version. Upgrade it deliberately, because the archive schema migrates often.
  - It publishes host port 8790 on all interfaces of the host and opens the port in the firewall. Reach it through caddy at `agentsview.local.jracon.xyz`. The bearer token of `/mnt/agentsview/config.toml` is the only gate on the dashboard.
  - The session directories of `dev` are read-only binds. The container reads and labels only. It never launches a session: the image holds no harness binary, and the binds are read-only.
  - It needs no secret of this repository. It generates its own bearer token into `/mnt/agentsview/config.toml` on first start. Read the token there.
  - The dispatcher does not depend on it. When the container is lost, the loop keeps working and only the audit degrades.
  - Telemetry stays off (`AGENTSVIEW_TELEMETRY_ENABLED = "0"`). Semantic search is off, because it is opt-in upstream.
- **wger** runs the full upstream service set except PowerSync: the app, an nginx server for the static files, Postgres 15, Redis, a Celery worker, and Celery beat. The module keeps the nginx container, because only it serves the static files correctly. Caddy proxies `wger.local.jracon.xyz` to host port 8888. The image tag is the exact release `2.7.0`. Upgrade it deliberately, because the image migrates the database at each start.
  - The entrypoint bootstraps a default admin user `admin` with the password `adminadmin`. Change the password at the first login. Registration stays off through `ALLOW_REGISTRATION = "False"`, so log in as `admin` and add users as an administrator.
  - REST API token login and the mobile app do not work: the JWT keys are unset and the PowerSync service is absent. Run `generate-jwt-keys` inside the `wger` container and add the service, when mobile sync is wanted.
  - The app reads its database URL from `PS_DATABASE_URI`, the upstream variable for PowerSync. The variable lives in `environment.age` beside `SECRET_KEY`, `SITE_URL`, and `CSRF_TRUSTED_ORIGINS`. The domains of this network stay out of the public mirror. `db_environment.age` holds the Postgres credentials, and the password must match the one inside `PS_DATABASE_URI`.
  - The directories `static`, `media`, and `beat` under `/mnt/wger/` belong to UID 1000, the container user of the image. The activation script sets that owner.

### Activation script naming

Use `create_<service>_directory` or `create_<service>_directories` for directories. Use `create_<service>-network` for networks. The attribute name has underscores. The network name has hyphens. Always assign to `.text`.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```
