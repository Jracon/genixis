# containers

Podman container services: the backend rules, the groups, the services, and the reverse proxy.

## What Is the Topic?

Two hosts run containers: `media` and `services` (flake.nix:441, 464). Host `media` loads the three media groups, and host `services` loads the service groups plus languagetool (flake.nix:438-463). One directory holds one service group, and a single file never orchestrates several services.

## How Is the Topic Realized?

Backend (modules/virtualisation/podman.nix): Podman with docker compatibility and the docker socket (podman.nix:8-21), and a daily prune of all images (podman.nix:12-19). Its default bridge network is `podman`, subnet `10.88.0.0/16`, gateway `10.88.0.1` (modules/services/dispatcher/dispatcher.nix:9-15).

Every container sets `pull = "newer"`, so an image is pulled only when a newer one exists (one `pull` line per service file). Every service stores its persistent data in bind mounts under `/mnt/<service>/`, and the shared media tree lives under `/mnt/media/`. Every published port has a firewall rule in the same file.

Groups and their services:

| Group | Service | Ports | Key facts |
| --- | --- | --- | --- |
| media-downloaders | gluetun | none | VPN gateway. It holds the tun device and the NET_ADMIN capability, and the activation script creates `gluetun-network` (gluetun.nix:19-37). |
| media-downloaders | deluge | 8112 | Torrent client. It joins `gluetun-network` and depends on gluetun (deluge.nix:16-26). |
| media-downloaders | sabnzbd | 8080 | Usenet client. It runs on the default network (sabnzbd.nix). |
| media-downloaders | shelfmark | 8084 | Book downloader of the calibre ingest. Calibre services mount its download directory as the ingest (shelfmark.nix:29-32; calibre.nix:26-31). |
| media-managers | sonarr, sonarr-anime | 8989, 8990 | Anime instance maps 8990 to the container port 8989 (sonarr.nix). |
| media-managers | radarr, radarr-anime | 7878, 7879 | Same pattern (radarr.nix). |
| media-managers | bazarr, bazarr-anime | 6767, 6768 | Same pattern (bazarr.nix). |
| media-managers | prowlarr | 9696 | Indexer manager (prowlarr.nix). |
| media-managers | seerr | 5055 | Request manager (seerr.nix). |
| media-managers | recyclarr | none | Config sync of the arr services. Its config is a secret (recyclarr.nix:18-32). |
| media-managers | calibre | 8181 | Library server. Ports 8081 and 8082 stay closed by the firewall (calibre.nix:2-4, 21-25). |
| media-managers | calibre-web-automated | 8083 | Web library. It shares the calibre library and the shelfmark ingest (calibre-web-automated.nix:10-31). |
| media-managers | kapowarr, kapowarr-manga | 5656, 5657 | Comic grabbers, one database each (kapowarr.nix). |
| media-servers | pool | none | Not a container. ZFS pool `media` that backs the media tree, with autoScrub and the hostId of the host (pool.nix:27-46). |
| media-servers | jellyfin | 8096, 8920, UDP 1900, 7359 | Media server. It runs with `--network=host` and the render device (jellyfin.nix:49-59). |
| media-servers | gamevault | 1337 | Game server with its own postgres on `gamevault-network` (gamevault.nix). |
| media-servers | romm | 9999 | Game library with mariadb and redis on `romm-network` (romm.nix). |
| media-servers | navidrome | 4533 | Music server (navidrome.nix). |
| media-servers | audiobookshelf | 13378 | Audiobook server (audiobookshelf.nix). |
| media-servers | kavita | 5000 | Reader (kavita.nix). |
| media-servers | syncthing | 8384, 22000, UDP 21027, 22000 | Container peer of the sync (media-servers/syncthing.nix). |
| forgejo | forgejo | 222, 4000 | Forge, image tag 17. Port 222 carries git over ssh, port 4000 the web. Runner `genixis_flake_update_runner` runs on the host label native (forgejo.nix:8-42, 54-78). |
| invidious | invidious, companion, db | 3000, 8282 | Video front end with its companion and postgres on `invidious-network`. A daily timer restarts the stack (invidious.nix:29-54). |
| dawarich | dawarich, db, redis | 3001 | Location history on `dawarich-network`. Its app entrypoint is overridden (dawarich.nix:27-43). |
| wger | wger, cache, db, nginx, celery | 8888 | Fitness suite on `wger-network`. Only nginx publishes a port. Its redis ceiling is one GiB with volatile-lru (wger.nix:127-143). |
| monica | monica, db | 1234 | CRM with mariadb on `monica-network` (monica.nix). |
| vaultwarden | vaultwarden | 5555 | Password store. A daily timer writes an age-encrypted backup under `/mnt/vaultwarden-backups` (vaultwarden.nix:22-65). |
| radicale | radicale | 5232 | Calendar and contact server. Its config and users are secrets (radicale.nix:8-42). |
| mealie | mealie | 9925 | Recipe manager (mealie.nix). |
| continuwuity | continuwuity | 8008 | Chat server, server name jracon.xyz (continuwuity.nix:16-27). |
| agentsview | agentsview | 8790 | Session monitor. It reads the claude projects directory read-only (agentsview.nix:29-35). |
| top level | languagetool | 8010 | Grammar server. Its activation script downloads the ngram data (languagetool.nix:7-13). |

Reverse proxy (modules/virtualisation/oci-containers/caddy/): Caddy terminates TLS for the wildcard `*.local.jracon.xyz`, with the certificate from DNS-01 through Cloudflare (Caddyfile:6-10). An environment names the Cloudflare token and the host addresses `HA_IP`, `MEDIA_IP`, and `SERVICES_IP` from a secret (caddy.nix:7-18; Caddyfile:1-4). Each route forwards to the published port of a host. One Caddyfile holds the route of every service above, under its host name, plus the route `ha` to a Home Assistant that this repository does not build (Caddyfile:72-75). No route exists for gluetun, which exposes no interface. A variable that the secret does not set expands to an empty value before Caddy parses the file; the runtime outcome of an empty value is unverified (the review of pull request 170, quoted on issue 218).

Each service secret is an agenix file; docs/secrets.md holds the inventory. Three patterns cover them: an environment file for variables, a mounted secret file for a config, and custom owner, group, and mode for a container user that is not root, as recyclarr and radicale set (recyclarr.nix:18-32; radicale.nix:8-18).

Per-service quirks that a change must know:

1. pool.nix picks the newest kernel whose ZFS module builds, imports the `media` pool, and sets a default hostId, because ZFS demands one and a local flake check needs a value (pool.nix:9-44). A real machine sets its own value, and a plain value wins over the default.
2. jellyfin runs with `--network=host` for the discovery protocols, and no other container takes that option (jellyfin.nix:57-59).
3. romm commits its config.yaml in the clear, and its mariadb tag follows the upstream compose file on purpose (romm.nix:49-59).
4. forgejo also runs the native runner of the CI. Label `native:host` runs each job directly on the host through the sandboxed nix-daemon. A docker label would add the runner to the rootful podman group, and a job container would run unsandboxed (forgejo.nix:8-52). Tools of a job go into its hostPackages.
5. dawarich embeds Sidekiq in the app container, and the module overrides the entrypoint of the image, which starts with bundle exec. Its web port is 3001, because invidious holds 3000 (dawarich.nix:27-43, 78-80).
6. agentsview pins an exact image tag, because the archive schema migrates often. It reads the session directories read-only, generates its own bearer token into `/mnt/agentsview/config.toml` on first start, and launches no session: the image holds no harness binary and the binds are read-only (agentsview.nix:15-35). Dispatcher holds no dependency on it, so the loop keeps working when the container is lost.
7. wger pins the release 2.7.0, because the image migrates the database at each start. Its entrypoint bootstraps the admin user once, registration stays off, and the mobile app does not work: the JWT keys are unset and the PowerSync service is absent (wger.nix:89-118). A database password must match the password inside the database URL of the secret (wger.nix:8-12).
8. Activation scripts follow one naming: `create_<service>_directory` or `create_<service>_directories` for directories, `create_<service>-network` for a network, with underscores in the attribute and hyphens in the network name.

One TODO sits in the container tree: the offsite backup of vaultwarden through rclone (vaultwarden.nix:48; docs/decisions.md, stopgap register, entry 5).

## Why Is the Topic That Way?

Service Law of this topic, at its application (docs/design.md holds the map):

1. Every service earns its port. An exposed port has a firewall rule. A sidecar database opens no port outside its isolated network.
2. Persistent data is a bind mount under the service directory in /mnt, never a named volume. Shared media lives under /mnt/media/.
3. One directory per service group. A single file never orchestrates several services.
4. Private traffic stays private. A torrent downloader routes through the VPN gateway, or it does not run. A service with no public consumer binds to the tailnet or the loopback only. Deluge joins the gluetun network. Sabnzbd and shelfmark download over usenet and http, so the law does not bind them.
5. A container pulls an image only when a newer one exists, through one `pull` line per service.
6. Services run on owned hardware, on the two servers of the owner (Stance item 2, docs/design.md).

## What Does the Topic Enable?

Purpose of the topic: the media stack and the utility services of the owner run from one declarative source, each with its data under `/mnt`, its proxy name, and its firewall rule. Service Law in the Why section of this file and the Necessity Tests of docs/design.md state the criteria.

## How Does a Reader Use and Change the Topic?

Add a service:

1. Write one file in the group directory, or one directory for a new group, under modules/virtualisation/oci-containers/.
2. Mount the persistent data under `/mnt/<service>/`, open the port in the firewall of the same file, and set `pull = "newer"`.
3. Add the secret, when the service needs one, the way docs/secrets.md states.
4. Add the route to the Caddyfile.
5. Add the group to the host list in flake.nix, run `nix fmt`, then `nix flake check --impure`.

Operator steps at a terminal, above all the log command `lgs`, live in docs/runbook.md.
