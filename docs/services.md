# services

The host services beyond the containers: the factory dispatcher, the tailnet, the sync, the Reticulum node, and the webdav share.

Domain: what. Reader: a session that changes a host service or the loop.
Code: modules/services/, lib/syncthing.nix.

## What is the topic?

Five host services run on the NixOS hosts:

1. The dispatcher on `services`: the factory loop that turns forge events into agent sessions (modules/services/dispatcher/).
2. Tailscale: `media` and `services` run the subnet router, `desktop` the client (modules/services/tailscale/).
3. Syncthing on `media` and `services`, with one container peer on `media` (modules/services/syncthing.nix; modules/virtualisation/oci-containers/media-servers/syncthing.nix).
4. The Reticulum node rnsd on `media` and `services` (modules/services/reticulum.nix).
5. The webdav share of the game saves on `services` (modules/services/rclone-webdav.nix).

## How is the topic realized?

The dispatcher (modules/services/dispatcher/dispatcher.nix):

1. The module activates only when the encrypted webhook secret is committed, and the user `dev` lingers (dispatcher.nix:55-67).
2. Three units run as systemd user services of `dev`: the receiver service, and the oneshots `dispatcher-run` and `dispatcher-poll` (dispatcher.nix:77-112).
3. The sweep timer runs every minute from boot. The poll timer is the fallback path and stays off by default (dispatcher.nix:115-137).
4. The receiver binds the podman bridge gateway `10.88.0.1` on port 8741, and the firewall opens the port on the podman interface only (dispatcher.nix:15-16, 69-91).
5. The unit environment sets `TMUX_TMPDIR` to the runtime directory of the user, so the view windows of the legs join the tmux server of the login (dispatcher.nix:38-48).
6. The receiver verifies the HMAC signature of each delivery and enqueues the event. The sweep claims one event per pass, with a minimum spacing of sixty seconds between spawns, and starts each leg with `project spawn --headless` inside its own scope (dispatcher/README.md:38-52, 116-145).
7. The exit codes 11 and 12 retry twice, code 7 pings the owner, and code 2 marks a dispatcher defect (dispatcher/README.md:127-130).
8. The full rule set of the loop, above all the leg types, the red gate, and the in-flight map, sits in the README of the module (modules/services/dispatcher/README.md).

The naming chain and the transport of the forge:

1. The repository owns no address for the forge name. The router DNS override resolves the name on the LAN, and the tailnet delegates `local.jracon.xyz` to the router through split DNS, so the name resolves wherever Tailscale runs (docs/decisions.md, record 2). Short host names resolve through MagicDNS on the tailnet, or through the DNS of the router on the LAN, which registers the DHCP host names under the search domain `localdomain` (modules/programs/cli/ssh.nix:28-29).
2. The state that this chain rests on sits outside the repository: the router override, the split DNS delegation, and the subnet-route toggle of the Tailscale app on the Mac (docs/decisions.md, record 2).
3. A claim of reachability names its process chain. The chains differ: a login shell, a tmux server, a background session, and a daemon each hold their own macOS Local Network state (the reachability record of 2026-11-08 on issue 204; issues 122 and 289).
4. No headless leg runs on Darwin. Headless legs run on `services`, because the macOS Local Network gate blocks the LAN address in a daemon chain (the transport record on issue 166; issues 122 and 289).

Tailscale (modules/services/tailscale/):

1. The server side on `media` and `services`: the auth key comes from the secret, the node advertises the subnet route `10.0.0.0/24` and the tag `tag:genixis`, and the firewall trusts the tailscale interface (server.nix:8-53).
2. A networkd dispatcher rule fixes the UDP receive offload of the default route interface (server.nix:32-44).
3. The client side on `desktop`: a one-time `tailscale up`, no auth key, no accepted routes, and the open firewall (client.nix:7-16).

Syncthing:

1. The service runs with its data under `/mnt/syncthing` and its default ports open (modules/services/syncthing.nix:11-20).
2. The topology, the devices and the folders, is committed in lib/syncthing.nix, and it is empty today. The device IDs stay out of the repository: each machine names them in its local.nix under `syncthing-device-ids` (lib/syncthing.nix:5-15, 36-39).
3. The Home Manager module reads the same topology, so both layers share one source (lib/syncthing.nix:5-6).

The Reticulum node: rnsd runs with the auto interface and the multicast ports open, and carries no transport (reticulum.nix:2-11).

The webdav share: rclone serves `/mnt/media/games/saves/` on port 8080 of `services`, with a dynamic user and no authentication (rclone-webdav.nix:18-40). The register holds the stopgap: authentication comes only if the retroarch client supports credentials (docs/decisions.md, stopgap register, entry 4).

## Why is the topic that way?

1. The loop is self-improving and runs on the self-hosted services of this repository (Stance item 7, docs/design-philosophy.md).
2. The dispatcher owns every launch of a session, and the chat interface reaches no launch or resume path of a daemon (Stance item 7; dispatcher/README.md:116-120).
3. The forge is reachable through several independent paths: the LAN, the tailnet with the subnet route, and the mirror (Stance item 6, docs/design-philosophy.md; docs/decisions.md, record 2).
4. The resilience layers that keep a spawn storm from freezing the host `services` sit in docs/host-resilience.md.
5. The dispatcher is security spine: it stays human-authored with agent assist (Layering item 1, docs/design-philosophy.md).

## What does the topic enable?

The end of the topic: the factory loop and the sync run on the hardware of the owner, unattended, and the forge answers through more than one path. Stance items 2 and 6 of docs/design-philosophy.md state the criteria.

## How does a reader use and change the topic?

Change the dispatcher:

1. Edit dispatcher.py or dispatcher.nix, and the README in the same commit.
2. Run `python3 modules/services/dispatcher/dispatcher-test.py` in the worktree when python3 is on the path. CI runs it on every pull request either way (.forgejo/workflows/ci.yaml:29-30).

Add a syncthing folder: declare the folder and its devices in lib/syncthing.nix, and name the device IDs in the local.nix of each machine.

Reach the forge over ssh: the route lives in docs/runbook.md, with the ssh layer of docs/secrets.md.
