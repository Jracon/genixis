# containers

Podman container services: the backend rules, the groups, the services, and the reverse proxy.

## Hosts and Groups

Two hosts run containers: `media` and `services`. Host `media` loads the three media groups. Host `services` loads one directory for each service group, plus the top-level file languagetool.nix. One directory holds one service group. expandModules in flake.nix expands a directory of a host list into every nix file beneath it.

## Backend Rules

podman.nix sets the container backend to Podman, with docker compatibility and the docker socket, and it prunes all images daily. Podman's default bridge network is `podman`, subnet `10.88.0.0/16`, gateway `10.88.0.1`. dispatcher.nix records these verified facts, because its webhook receiver binds the gateway.

Every container sets `pull = "newer"`, so an image is pulled only when a newer one exists. Each service file carries its own pull line. Every service stores its persistent data in bind mounts under `/mnt/<service>/`, and the shared media tree lives under `/mnt/media/`. Every published port has a firewall rule in the same file.

## Service Groups

Groups and their services:

| Group | Service | Ports | Key facts |
| --- | --- | --- | --- |
| media-downloaders | gluetun | none | VPN gateway. It holds the tun device and the NET_ADMIN capability, and its activation script creates `gluetun-network`. |
| media-downloaders | deluge | 8112 | Torrent client. It joins `gluetun-network` and depends on gluetun. |
| media-downloaders | sabnzbd | 8080 | Usenet client. It runs on the default network. |
| media-downloaders | shelfmark | 8084 | Book downloader of the calibre ingest. Calibre services mount its download directory as the ingest. |
| media-managers | sonarr, sonarr-anime | 8989, 8990 | Anime instance maps 8990 to the container port 8989. |
| media-managers | radarr, radarr-anime | 7878, 7879 | Same pattern. |
| media-managers | bazarr, bazarr-anime | 6767, 6768 | Same pattern. |
| media-managers | prowlarr | 9696 | Indexer manager. |
| media-managers | seerr | 5055 | Request manager. |
| media-managers | recyclarr | none | Config sync of the arr services. Its config is a secret. |
| media-managers | calibre | 8181 | Library server. Ports 8081 and 8082 stay closed by the firewall. |
| media-managers | calibre-web-automated | 8083 | Web library. It shares the calibre library and the shelfmark ingest. |
| media-managers | kapowarr, kapowarr-manga | 5656, 5657 | Comic grabbers, one database each. |
| media-servers | pool | none | Not a container. ZFS pool `media` that backs the media tree, with autoScrub and a default hostId that the host overrides. |
| media-servers | jellyfin | 8096, 8920, UDP 1900, 7359 | Media server. It runs with host networking and the render device. A daily root timer runs playlist_generator.sh from the /mnt/media tree. |
| media-servers | gamevault | 1337 | Game server with its own postgres on `gamevault-network`. |
| media-servers | romm | 9999 | Game library with mariadb and redis on `romm-network`. |
| media-servers | navidrome | 4533 | Music server. |
| media-servers | audiobookshelf | 13378 | Audiobook server. |
| media-servers | kavita | 5000 | Reader. |
| media-servers | syncthing | 8384, 22000, UDP 21027, 22000 | Container peer of the sync (media-servers/syncthing.nix). |
| forgejo | forgejo | 222, 4000 | Forge, image tag 17. Port 222 carries git over ssh, port 4000 the web. The CI runner of the forge runs on the host itself (docs/ci.md). |
| invidious | invidious, companion, db | 3000, 8282 | Video front end with its companion and postgres on `invidious-network`. A daily timer restarts the app container. |
| dawarich | dawarich, db, redis | 3001 | Location history on `dawarich-network`. Its app entrypoint is overridden. |
| wger | wger, cache, db, nginx, celery | 8888 | Fitness suite on `wger-network`. Only nginx publishes a port. Its redis ceiling is one GiB with volatile-lru. |
| monica | monica, db | 1234 | CRM with mariadb on `monica-network`. |
| vaultwarden | vaultwarden | 5555 | Password store. A daily timer writes an age-encrypted backup under `/mnt/vaultwarden-backups`. |
| radicale | radicale | 5232 | Calendar and contact server. Its config and users are secrets. |
| mealie | mealie | 9925 | Recipe manager. |
| continuwuity | continuwuity | 8008 | Chat server, server name jracon.xyz. |
| agentsview | agentsview | 8790 | Session monitor. It reads the claude projects directory read-only. |
| top level | languagetool | 8010 | Grammar server. Its activation script downloads the ngram data. |

## Reverse Proxy

caddy.nix and the Caddyfile of modules/virtualisation/oci-containers/caddy/ run one Caddy container. Caddy terminates TLS for the wildcard `*.local.jracon.xyz`, with the certificate from DNS-01 through Cloudflare. An environment names the Cloudflare token and the host addresses `HA_IP`, `MEDIA_IP`, and `SERVICES_IP` from a secret. Each route forwards to the published port of a host. One route exists for each service that publishes a port, under its host name. Gluetun, recyclarr, and pool expose no interface, so they hold no route. A route `ha` forwards to a Home Assistant that this repository does not build. A variable that the secret does not set expands to an empty value before Caddy parses the file; the runtime outcome of an empty value is unverified (the review of pull request 170, quoted on issue 218).

## Secret Patterns

Each service secret is an agenix file; docs/secrets.md holds the inventory. Three patterns cover them: an environment file for variables, a mounted secret file for a config, and custom file ownership for a container user that is not root. Recyclarr sets owner, group, and mode; radicale sets owner and group.

## Service Quirks

Per-service quirks that a change must know:

1. pool.nix picks the newest kernel whose ZFS module builds and imports the `media` pool. Workaround record, the default hostId. Context: ZFS demands a hostId, and a local flake check needs a value with no machine state. Decision: pool.nix sets a default hostId, and a plain value of the machine wins over it. Options that lost: no default value, because a local flake check fails without one. Consequences: the default reaches no real machine. Status: deferred. Cause: no verdict says whether the default is a standing pattern. Trigger and end: the owner takes the verdict, and the ruling lands in this record.
2. jellyfin runs with host networking, and no other container takes that option.
3. romm commits its config.yaml in the clear. Its mariadb tag follows the upstream example compose. An upstream check on 2026-11-12 confirmed the match.
4. forgejo also runs the native runner of the CI on the host itself, and the container holds no runner state. docs/ci.md holds the runner facts, above all the sandboxed nix-daemon and the tool sources of a job.
5. dawarich embeds Sidekiq in the app container, and the module overrides the entrypoint of the image, which starts with bundle exec. Its web port is 3001, because invidious holds 3000.
6. agentsview pins an exact image tag. It binds the session directories of dev read-only. Dispatcher holds no dependency on it, so the loop keeps working when the container is lost.
7. wger pins the release 2.7.0. Its first start loads the fixtures, collects the static files, and migrates the database, so its health check grants a long start period. Registration stays off. A database password must match the password inside the database URL of the secret.
8. Activation scripts follow one naming: `create_` plus the service name plus `_directory` or `_directories` for directories, and `create_` plus the service name plus `-network` for a network. Each attribute keeps the service name as written, so calibre-web-automated keeps its hyphens. Three scripts sit outside the naming, because they do more than create: `copy_invidious_files` also copies the sql schema of the flake input, `download_languagetool_ngrams` also downloads the ngram data, and `create_vaultwarden_encryption_key` writes the public key of the age recipient.
9. vaultwarden writes a daily age-encrypted backup under `/mnt/vaultwarden-backups`. One TODO sits in the container tree: the offsite backup of vaultwarden through rclone. Workaround record: no offsite backup location exists. Verdict: pending. An offsite backup location is the review trigger, and a daily local backup already runs.

## Service Law

Service Law of this topic, at its application (docs/design.md holds the map):

1. Every service earns its port. An exposed port has a firewall rule. A sidecar database opens no port outside its isolated network.
2. Persistent data is a bind mount under the service directory in /mnt, never a named volume. Shared media lives under /mnt/media/.
3. One directory per service group. A single file never orchestrates several services.
4. Private traffic stays private. A torrent downloader routes through the VPN gateway, or it does not run. A service with no public consumer binds to the tailnet or the loopback only. Deluge joins the gluetun network. Sabnzbd and shelfmark download over usenet and http, so the law does not bind them.
5. A container pulls an image only when a newer one exists, through one `pull` line per service.
6. Every container runs on one of the two servers of the owner (Stance item 2, docs/design.md).

## Purpose of the Services

Purpose of the topic: the media stack and the utility services of the owner run from one declarative source, each with its data under `/mnt` and, when it publishes a port, its proxy name and its firewall rule. Service Law above and the Necessity Tests of docs/design.md state the criteria.

## Add a Service

1. Write one file in the group directory, or one directory for a new group, under modules/virtualisation/oci-containers/.
2. Mount the persistent data under `/mnt/<service>/`, open the port in the firewall of the same file, and set `pull = "newer"`.
3. Add the secret, when the service needs one, the way docs/runbook.md states.
4. Add the route to the Caddyfile.
5. Add the group to the host list in flake.nix, run `nix fmt`, then `nix flake check --impure`.

Operator steps at a terminal, above all the log command `lgs`, live in docs/runbook.md.
