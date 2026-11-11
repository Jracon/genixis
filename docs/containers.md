# containers

The Podman container services: the backend rules, the groups, the services, and the reverse proxy.

Domain: what. Reader: a session that adds or changes a container service.
Code: modules/virtualisation/.

## What is the topic?

Two hosts run containers: `media` and `services` (flake.nix:441, 464). The host `media` loads the three media groups, and the host `services` loads the service groups plus languagetool (flake.nix:438-463). One directory holds one service group, and a flat file never orchestrates several services (Service law item 3, docs/design-philosophy.md).

## How is the topic realized?

The backend (modules/virtualisation/podman.nix): Podman with docker compatibility and the docker socket (podman.nix:8-21), and a daily prune of all images (podman.nix:12-19). The default bridge network is `podman`, subnet `10.88.0.0/16`, gateway `10.88.0.1` (modules/services/dispatcher/dispatcher.nix:9-15).

Every container sets `pull = "newer"`, so an image is pulled only when a newer one exists (one `pull` line per service file). Every service stores its persistent data in bind mounts under `/mnt/<service>/`, and the shared media tree lives under `/mnt/media/` (Service law item 2). Every published port has a firewall rule in the same file (Service law item 1).

The groups and their services:

| Group | Service | Ports | Key facts |
| --- | --- | --- | --- |
| media-downloaders | gluetun | none | The VPN gateway. It holds the tun device and the NET_ADMIN capability, and the activation script creates `gluetun-network` (gluetun.nix:19-37). |
| media-downloaders | deluge | 8112 | The torrent client. It joins `gluetun-network` and depends on gluetun (deluge.nix:16-26). |
| media-downloaders | sabnzbd | 8080 | The usenet client. It runs on the default network (sabnzbd.nix). |
| media-downloaders | shelfmark | 8084 | The book downloader of the calibre ingest. The calibre services mount its download directory as the ingest (shelfmark.nix:29-32; calibre.nix:26-31). |
| media-managers | sonarr, sonarr-anime | 8989, 8990 | The anime instance maps 8990 to the container port 8989 (sonarr.nix). |
| media-managers | radarr, radarr-anime | 7878, 7879 | Same pattern (radarr.nix). |
| media-managers | bazarr, bazarr-anime | 6767, 6768 | Same pattern (bazarr.nix). |
| media-managers | prowlarr | 9696 | The indexer manager (prowlarr.nix). |
| media-managers | seerr | 5055 | The request manager (seerr.nix). |
| media-managers | recyclarr | none | The config sync of the arr services. Its config is a secret (recyclarr.nix:18-32). |
| media-managers | calibre | 8181 | The library server. Ports 8081 and 8082 stay closed by the firewall (calibre.nix:2-4, 21-25). |
| media-managers | calibre-web-automated | 8083 | The web library. It shares the calibre library and the shelfmark ingest (calibre-web-automated.nix:10-31). |
| media-managers | kapowarr, kapowarr-manga | 5656, 5657 | The comic grabbers, one database each (kapowarr.nix). |
| media-servers | pool | none | Not a container. The ZFS pool `media` that backs the media tree, with autoScrub and the hostId of the host (pool.nix:27-46). |
| media-servers | jellyfin | 8096, 8920, UDP 1900, 7359 | The media server. It runs with `--network=host` and the render device (jellyfin.nix:49-59). |
| media-servers | gamevault | 1337 | The game server with its own postgres on `gamevault-network` (gamevault.nix). |
| media-servers | romm | 9999 | The game library with mariadb and redis on `romm-network` (romm.nix). |
| media-servers | navidrome | 4533 | The music server (navidrome.nix). |
| media-servers | audiobookshelf | 13378 | The audiobook server (audiobookshelf.nix). |
| media-servers | kavita | 5000 | The reader (kavita.nix). |
| media-servers | syncthing | 8384, 22000, UDP 21027, 22000 | The container peer of the sync (media-servers/syncthing.nix). |
| forgejo | forgejo | 222, 4000 | The forge, image tag 17. Port 222 carries git over ssh, port 4000 the web. The runner `genixis_flake_update_runner` runs on the host label native (forgejo.nix:8-42, 54-78). |
| invidious | invidious, companion, db | 3000, 8282 | The video front end with its companion and postgres on `invidious-network`. A daily timer restarts the stack (invidious.nix:29-54). |
| dawarich | dawarich, db, redis | 3001 | The location history on `dawarich-network`. The entrypoint of the app is overridden (dawarich.nix:27-43). |
| wger | wger, cache, db, nginx, celery | 8888 | The fitness suite on `wger-network`. Only nginx publishes a port. The redis ceiling is one GiB with volatile-lru (wger.nix:127-143). |
| monica | monica, db | 1234 | The CRM with mariadb on `monica-network` (monica.nix). |
| vaultwarden | vaultwarden | 5555 | The password store. A daily timer writes an age-encrypted backup under `/mnt/vaultwarden-backups` (vaultwarden.nix:22-65). |
| radicale | radicale | 5232 | The calendar and contact server. Its config and users are secrets (radicale.nix:8-42). |
| mealie | mealie | 9925 | The recipe manager (mealie.nix). |
| continuwuity | continuwuity | 8008 | The chat server, server name jracon.xyz (continuwuity.nix:16-27). |
| agentsview | agentsview | 8790 | The session monitor. It reads the claude projects directory read-only (agentsview.nix:29-35). |
| top level | languagetool | 8010 | The grammar server. The activation script downloads the ngram data (languagetool.nix:7-13). |

The reverse proxy (modules/virtualisation/oci-containers/caddy/): Caddy terminates TLS for the wildcard `*.local.jracon.xyz`, with the certificate from DNS-01 through Cloudflare (Caddyfile:6-10). The environment names the Cloudflare token and the host addresses `HA_IP`, `MEDIA_IP`, and `SERVICES_IP` from a secret (caddy.nix:7-18; Caddyfile:1-4). Each route forwards to the published port of a host. The Caddyfile holds the route of every service above, under its host name, plus the route `ha` to a Home Assistant that this repository does not build (Caddyfile:72-75). No route exists for gluetun, which exposes no interface.

The secret of each service is an agenix file; docs/secrets.md holds the inventory.

One TODO sits in the container tree: the offsite backup of vaultwarden through rclone (vaultwarden.nix:48; docs/decisions.md, stopgap register, entry 5).

## Why is the topic that way?

1. Every service earns its port: an exposed port has a firewall rule, and a sidecar database opens no port outside its isolated network (Service law item 1, docs/design-philosophy.md).
2. Persistent data is a bind mount under `/mnt/<service>/`, never a named volume (Service law item 2).
3. Private traffic stays private: a torrent downloader routes through the VPN gateway or does not run, and a service with no public consumer binds to the tailnet or the loopback only (Service law item 4). Deluge joins the gluetun network; sabnzbd and shelfmark download over usenet and http, so the law does not bind them.
4. A container pulls an image only when a newer one exists (Service law item 5), through one `pull` line per service.
5. The services run on owned hardware, on the two servers of the owner (Stance item 2, docs/design-philosophy.md).

## What does the topic enable?

The end of the topic: the media stack and the utility services of the owner run from one declarative source, each with its data under `/mnt`, its proxy name, and its firewall rule. The Service law and the necessity tests of docs/design-philosophy.md state the criteria.

## How does a reader use and change the topic?

Add a service:

1. Write one file in the group directory, or one directory for a new group, under modules/virtualisation/oci-containers/.
2. Mount the persistent data under `/mnt/<service>/`, open the port in the firewall of the same file, and set `pull = "newer"`.
3. Add the secret, when the service needs one, the way docs/secrets.md states.
4. Add the route to the Caddyfile.
5. Add the group to the host list in flake.nix, run `nix fmt`, then `nix flake check --impure`.

The operator steps at a terminal, above all the log command `lgs`, live in docs/runbook.md.
