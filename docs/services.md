# services

Host services beyond the containers: the factory dispatcher, the tailnet, the sync, the Reticulum node, and the webdav share.

## What Is the Topic?

Five host services run on the NixOS hosts:

1. Dispatcher on `services`: the factory loop that turns forge events into agent sessions (modules/services/dispatcher/).
2. Tailscale: `media` and `services` run the subnet router, `desktop` the client (modules/services/tailscale/).
3. Syncthing on `media` and `services`, with one container peer on `media` (modules/services/syncthing.nix; modules/virtualisation/oci-containers/media-servers/syncthing.nix).
4. Reticulum node rnsd on `media` and `services` (modules/services/reticulum.nix).
5. Webdav share of the game saves on `services` (modules/services/rclone-webdav.nix).

## How Is the Topic Realized?

Dispatcher (modules/services/dispatcher/dispatcher.nix):

1. A module activates only when the encrypted webhook secret is committed, and the user `dev` lingers (dispatcher.nix:55-67).
2. Three units run as systemd user services of `dev`: the receiver service, and the oneshots `dispatcher-run` and `dispatcher-poll` (dispatcher.nix:77-112).
3. A sweep timer runs every minute from boot. A poll timer is the fallback path and stays off by default (dispatcher.nix:115-137).
4. A receiver binds the podman bridge gateway `10.88.0.1` on port 8741, and the firewall opens the port on the podman interface only (dispatcher.nix:15-16, 69-91).
5. A unit environment sets `TMUX_TMPDIR` to the runtime directory of the user, so the view windows of the legs join the tmux server of the login (dispatcher.nix:38-48).
6. A receiver verifies the HMAC signature of each delivery and enqueues the event. A sweep claims one event per pass, with a minimum spacing of sixty seconds between spawns, and starts each leg with `project spawn --headless` inside its own scope (dispatcher/README.md:38-52, 116-145).
7. Exit codes 11 and 12 retry twice, code 7 pings the owner, and code 2 marks a dispatcher defect (dispatcher/README.md:127-130).
8. Full rules of the loop, above all the leg types, the red gate, and the in-flight map, sit in the README of the module (modules/services/dispatcher/README.md).

Deferred with a trigger: beads as a runtime dependency, when the shared queue earns it.

Naming chain and transport of the forge:

1. This repository owns no address for the forge name. A router DNS override resolves the name on the LAN, and the tailnet delegates `local.jracon.xyz` to the router through split DNS, so the name resolves wherever Tailscale runs (docs/decisions.md, record 2). Short host names resolve through MagicDNS on the tailnet, or through the DNS of the router on the LAN, which registers the DHCP host names under the search domain `localdomain` (modules/programs/cli/ssh.nix:28-29).
2. State that this chain rests on sits outside the repository: the router override, the split DNS delegation, and the subnet-route toggle of the Tailscale app on the Mac (docs/decisions.md, record 2).
3. A claim of reachability names its process chain. Chains differ: a login shell, a tmux server, a background session, and a daemon each hold their own macOS Local Network state (the reachability record of 2026-11-08 on issue 204; issues 122 and 289). A background session runs under a daemon host, and the grant follows the parent of that host: a daemon host that launchd starts holds no grant, and one that a session inside tmux starts inherits the grant of the tmux server (issue 289). A probe of a background session names the parent of its daemon host before it reads the reachability as evidence.
4. No headless leg runs on Darwin. Headless legs run on `services`, because the macOS Local Network gate blocks the LAN address in a daemon chain (the transport record on issue 166; issues 122 and 289).

Workaround record, ssh route of the forge over MagicDNS in the ssh config secret: the launchd tmux server agent removed the cause, a macOS Local Network privacy block of the LAN for a tmux server that WezTerm had started (modules/programs/cli/tmux.nix:71-100). Verdict: keep as a stated design. Decision record 2 supersedes the transport half of this record.

Tailscale (modules/services/tailscale/):

1. Server side on `media` and `services`: the auth key comes from the secret and is non-ephemeral by explicit setting, the node advertises the subnet route `10.0.0.0/24` and the tag `tag:genixis`, and the firewall trusts the tailscale interface (server.nix:8-53).
2. A networkd dispatcher rule fixes the UDP receive offload of the default route interface, a tuning for the subnet routing (server.nix:32-44).
3. Client side on `desktop`: a one-time `tailscale up`, no auth key, no accepted routes, and the open firewall (client.nix:7-16). Its client accepts no routes on purpose: it sits on the LAN that the servers advertise, and accepted routes would carry its LAN replies out over the tailnet (client.nix:13-15).
4. Mac is the one client that accepts the subnet routes. It runs an App Store app, which the flake installs but cannot manage, and the setting Use Tailscale Subnets holds the toggle, so a reinstall needs the toggle again (the transport record on issue 166).
5. Split DNS delegation of `local.jracon.xyz` sits in the admin console of the tailnet, and the flake does not manage it. Read the state of a node with `tailscale dns status` (the transport record on issue 166).

Syncthing:

1. Syncthing runs with its data under `/mnt/syncthing` and its default ports open (modules/services/syncthing.nix:11-20).
2. Topology, the devices and the folders, is committed in lib/syncthing.nix, and it is empty today. Device IDs stay out of the repository: each machine names them in its local.nix under `syncthing-device-ids`, and a peer without an ID is skipped, so CI evaluates without them (lib/syncthing.nix:5-15, 36-39).
3. A host syncs only the folders that list it. Folders land under the data directory of the host, and the Home Manager side reads the same topology for the non-root users, so both layers share one source (lib/syncthing.nix:17-20; modules/programs/cli/syncthing.nix).

Reticulum node (modules/services/reticulum.nix; issue 233):

1. rnsd runs as an AutoInterface node that discovers peers through UDP multicast, with the ports open (reticulum.nix:2-10).
2. Scope of the phase: the transport mode stays off, and the one interface section carries the peer discovery (reticulum.nix:6-11).
3. A daemon runs under a dynamic user and keeps its generated identity under /var/lib/rnsd. This repository commits no identity (reticulum.nix).
4. CLI tools come from pkgs.rns for every Home Manager user (modules/programs/cli/packages.nix:13). Each user holds one instance beside the daemon, because each reads its own config directory.

Webdav share: rclone serves `/mnt/media/games/saves/` on port 8080 of `services`, with a dynamic user and no authentication (rclone-webdav.nix:18-40). A service opens no firewall port, so only the trusted tailscale interface and the loopback reach it. Do not open the port to the public. Workaround record: its only consumer is the sync of retroarch saves. Verdict: conditional solve. Add authentication only when the retroarch webdav client supports credentials. Otherwise keep the service as a stated design, with the retroarch reason.

## Why Is the Topic That Way?

1. Natural language is an interface, not a dependency. Instruction reaches the loop over text, also away from a terminal, and it never reaches a launch or resume path of a daemon. Dispatcher owns every launch of a session (Stance item 8, docs/design.md; dispatcher/README.md:116-120).
2. A self-improving loop. It improves the work of the repository, and it runs on the self-hosted services of this repository (Stance item 9, docs/design.md).
3. Resilience by avenue count. Several independent paths reach the forge: the LAN, the tailnet with the subnet route, and the mirror (Stance item 6, docs/design.md; docs/decisions.md, record 2).
4. Everything that reaches the owner passed an agent review first. A queue of the owner holds only reviewed pull requests.
5. Agent-generated state joins the backup set as it appears: transcripts, memory, dispatcher state.
6. Dispatcher is security spine: it stays human-authored with agent assist.
7. Resilience layers that keep a spawn storm from freezing the host `services` sit in docs/host-resilience.md.

## What Does the Topic Enable?

Purpose of the topic: the factory loop and the sync run on the hardware of the owner, unattended, and the forge answers through more than one path. Stance items 2 and 6 of docs/design.md state the criteria.

## How Does a Reader Use and Change the Topic?

Change the dispatcher:

1. Edit dispatcher.py or dispatcher.nix, and the README in the same commit.
2. Run `python3 modules/services/dispatcher/dispatcher-test.py` in the worktree when python3 is on the path. CI runs it on every pull request either way (.forgejo/workflows/ci.yaml:29-30).

Add a syncthing folder: declare the folder and its devices in lib/syncthing.nix, and name the device IDs in the local.nix of each machine.

Reach the forge over ssh: the route lives in docs/runbook.md, with the ssh layer of docs/secrets.md.
