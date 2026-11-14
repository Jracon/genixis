# services

Host services beyond the containers: the factory dispatcher, the tailnet, the sync, the Reticulum node, the webdav share, and the layers that keep a spawn storm off the host `services`.

## Five Host Services

Five host services run on the NixOS hosts:

1. Dispatcher on `services`: the factory loop that turns forge events into agent sessions (modules/services/dispatcher/).
2. Tailscale: `media` and `services` run the subnet router, `desktop` the client (modules/services/tailscale/).
3. Syncthing on `media` and `services`, with one container peer on `media` (modules/services/syncthing.nix; modules/virtualisation/oci-containers/media-servers/syncthing.nix).
4. Reticulum node rnsd on `media` and `services` (modules/services/reticulum.nix).
5. Webdav share of the game saves on `services` (modules/services/rclone-webdav.nix).

## Dispatcher

Dispatcher rules, at their realization in modules/services/dispatcher/dispatcher.nix:

1. A module activates only when the encrypted webhook secret is committed, and the user `dev` lingers.
2. Three units run as systemd user services of `dev`: the receiver service, and the oneshots `dispatcher-run` and `dispatcher-poll`.
3. A sweep timer runs every minute from boot. A poll timer is the fallback path and stays off by default.
4. A receiver binds the podman bridge gateway `10.88.0.1` on port 8741, and the firewall opens the port on the podman interface only.
5. A unit environment sets `TMUX_TMPDIR` to the runtime directory of the user, so the view windows of the legs join the tmux server of the login.
6. A receiver verifies the HMAC signature of each delivery and enqueues the event. A sweep claims one event per pass, with a minimum spacing of sixty seconds between spawns, and starts each leg with `project spawn --headless` inside its own scope.
7. Exit codes 11 and 12 retry twice, code 7 pings the owner, and code 2 marks a dispatcher defect (dispatcher/README.md).
8. A readiness gate parks an issue whose brief answers no ambiguity class of the factory skill, with the missing classes named in one comment, and no leg starts (dispatcher/README.md).
9. Full rules of the loop, above all the leg types, the readiness gate, the red gate, and the in-flight map, sit in the README of the module.

Deferred with a trigger: beads as a runtime dependency, when the shared queue earns it.

## Naming Chain of the Forge

1. This repository owns no address for the forge name. A router DNS override resolves the name on the LAN, and the tailnet delegates `local.jracon.xyz` to the router through split DNS, so the name resolves wherever Tailscale runs (docs/adr/forge-naming-chain.md). Short host names resolve through MagicDNS on the tailnet, or through the DNS of the router on the LAN, which registers the DHCP host names under the search domain `localdomain` (ssh.nix).
2. State that this chain rests on sits outside the repository: the router override, the split DNS delegation, and the subnet-route toggle of the Tailscale app on the Mac (docs/adr/forge-naming-chain.md).
3. A claim of reachability names its process chain. Chains differ: a login shell, a tmux server, a background session, and a daemon each hold their own macOS Local Network state (the reachability record of 2026-11-08 on issue 204; issues 122 and 289). A background session runs under a daemon host, and the grant follows the parent of that host: a daemon host that launchd starts holds no grant, and one that a session inside tmux starts inherits the grant of the tmux server (issue 289). A probe of a background session names the parent of its daemon host before it reads the reachability as evidence.
4. No headless leg runs on Darwin. Headless legs run on `services`, because the macOS Local Network gate blocks the LAN address in a daemon chain (the transport record on issue 166; issues 122 and 289).

Workaround record, the ssh route of the forge in the ssh config secret (docs/adr/earlier-records-clause-scope.md). Context: a macOS Local Network privacy block once stopped a tmux server that WezTerm had started from reaching the LAN, and the route over MagicDNS filled the gap. Decision: the ssh config secret keeps the route, and the launchd tmux server agent removed the cause (tmux.nix). Options that lost: the transport alternatives live in docs/adr/forge-naming-chain.md, which supersedes the transport half of this record. Consequences: the route stays in the secret after its cause ended. Status: keep as a stated design. Reopen trigger: the next rewrite of the ssh config secret. When the trigger fires, the route can leave the secret at no extra cost.

## Tailscale

1. Server side on `media` and `services`: the auth key comes from the secret and is non-ephemeral by explicit setting, the node advertises the subnet route `10.0.0.0/24` and the tag `tag:genixis`, and the firewall trusts the tailscale interface (server.nix).
2. A networkd dispatcher rule fixes the UDP receive offload of the default route interface, a tuning for the subnet routing (server.nix).
3. Client side on `desktop`: a one-time `tailscale up`, no auth key, no accepted routes, and the open firewall (client.nix). Its client accepts no routes on purpose: it sits on the LAN that the servers advertise, and accepted routes would carry its LAN replies out over the tailnet.
4. Mac is the one client that accepts the subnet routes. It runs an App Store app, which the flake installs but cannot manage, and the setting Use Tailscale Subnets holds the toggle, so a reinstall needs the toggle again (the transport record on issue 166).
5. Split DNS delegation of `local.jracon.xyz` sits in the admin console of the tailnet, and the flake does not manage it. Read the state of a node with `tailscale dns status` (the transport record on issue 166).

## Syncthing

1. Syncthing runs with its data under `/mnt/syncthing` and its default ports open (modules/services/syncthing.nix).
2. Topology, the devices and the folders, is committed in lib/syncthing.nix, and it is empty today. Device IDs stay out of the repository: each machine names them in its local.nix under `syncthing-device-ids`, and a peer without an ID is skipped, so CI evaluates without them.
3. A host syncs only the folders that list it. Folders land under the data directory of the host, and the Home Manager side reads the same topology for the non-root users, so both layers share one source (modules/programs/cli/syncthing.nix).

## Reticulum Node

1. rnsd runs as an AutoInterface node that discovers peers through UDP multicast, with the ports open (reticulum.nix; issue 233).
2. Scope of the phase: the transport mode stays off, and the one interface section carries the peer discovery.
3. A daemon runs under a dynamic user and keeps its generated identity under /var/lib/rnsd. This repository commits no identity.
4. CLI tools come from pkgs.rns for every Home Manager user (packages.nix). Each user holds one instance beside the daemon, because each reads its own config directory.

## Webdav Share

rclone serves `/mnt/media/games/saves/` on port 8080 of `services`, with a dynamic user and no authentication (rclone-webdav.nix). A service opens no firewall port, so only the trusted tailscale interface and the loopback reach it. Do not open the port to the public. Workaround record, the share without authentication (docs/adr/earlier-records-clause-scope.md). Context: the only consumer of the share is the sync of retroarch saves, and the retroarch client supports no credentials. Decision: the service runs with no authentication. Options that lost: authentication on the service, because the consumer supports none. Consequences: the sync needs no login, and every peer of the tailnet can read the share. Status: keep as a stated design. Reopen trigger: a retroarch webdav client that supports credentials. When the trigger fires, the status moves to solve, and the service gains authentication.

## Spawn-Storm Resilience

Four layers bound every spawn storm on the host `services`, ranked by how much future they survive (issue 267):

1. Memory boundary: the slice `user-1000` carries `MemoryHigh = 10G` and `MemoryMax = 12G` as a drop-in, and the module pins the uid of `dev` to 1000 with an assertion (user-slice-memory.nix). Every spawn path lands in the user slice, also paths that do not exist today, so this layer bounds every storm.
2. Zram: enabled at fifty percent of memory, an eight GiB device on the sixteen GiB host (zram.nix).
3. Watchdog: the softdog kernel module loads as the fallback, and `RuntimeWatchdogSec = 30s` makes PID 1 ping the device about every fifteen seconds. A hang resets the host within about thirty seconds (watchdog.nix). A reset takes the node cleanly offline, so the tailnet failover to `media` engages.
4. Spawn gate: `project spawn` and `project ide open` read the memory headroom of the host and refuse below two GiB, with exit code 12. Dispatcher retries the refusal twice (memorygate.go; dispatcher/README.md).

Dispatcher adds its own pacing: one leg per sweep pass and a minimum spacing of sixty seconds (Dispatcher section above).

Why these layers: on 2026-11-09, thirteen session windows in ninety-five seconds filled the sixteen GiB host with anonymous pages. That host ran no swap, so the kernel could only reclaim page cache: every executable page faulted in, was evicted, and faulted again, and the host ran at about one percent speed for sixteen minutes until a power cut. Allocation always succeeded, so the OOM killer never ran. This is the no-swap livelock (issue 267). The kernel boundary is first because it needs no cooperation; zram turns the pressure into degradation; the watchdog catches the rest; the tool gate is fourth because an agent can bypass the tool with raw tmux (issue 267).

Three refinements landed with the layers:

1. Slice cap covers the session scopes of ssh logins too, not only the user manager, because a tmux server that an ssh login starts lands in the session scope of that login (issue 271; user-slice-memory.nix).
2. Gate reads MemAvailable plus SwapFree, and it fails open on a host without /proc/meminfo, because it is a courtesy layer (memorygate.go).
3. Ide builder answers for an open window before the gate runs, so an open window stays reachable below the floor, because it is where a person stops a session (issue 273; cmd_ide.go).

Deferred with a trigger: the microVM tier, only if Seatbelt or the proxy fail.

Owner verifies the layers after a rebuild of services (issue 267, acceptance):

1. Storm test: open thirteen session windows inside two minutes from an ssh login of dev, with project spawn and a five-second sleep between them. A host passes when ssh answers, one container answers on its port, and the subnet route stays up. Close the stress worktrees afterwards.
2. Hang test: freeze init.scope as root with a write of 1 to /sys/fs/cgroup/init.scope/cgroup.freeze. A root cgroup itself exposes no freeze file, so init.scope is the path that runs (issue 272). This command resets the host by design.
3. Failover test: during the hang, from a client off the LAN, reach one address of 10.0.0.0/24 through media, and after the reset reach it again with no manual step.

Open verifications, with no recorded outcome:

1. Hardware watchdog of the host `services` with wdctl. Softdog stays the fallback until it passes (watchdog.nix; issue 267).
2. Three owner tests above.
3. Re-measure of the standing stack.

Register of pending owner actions tracks them (issue 236).

## Loop Observability

1. The surface of the loop is the board, the agent view, and the derived record of a campaign. No tool beyond these three is built (issue 356, L10).
2. The board: `project board` joins the frontier of the project with the open issues and the open pull requests of the forge, read through tea with no write (cmd_board.go). Verified 2026-11-13: the command is wired, its join holds tests (cmd_board_test.go), and the surface record of its build is the comment of 2026-11-06 on issue 102.
3. The agent view: `claude agents` lists the background sessions of the legs, and `claude attach` opens one. The view window of a leg shows its work live (dispatcher/README.md).
4. The derived record: the campaign close record of the factory skill derives from the forge and from the transcripts of the harness. The loop writes no second record (issue 350, D13).

## Loop and Reachability

1. Natural language is an interface, not a dependency. Instruction reaches the loop over text, also away from a terminal, and it never reaches a launch or resume path of a daemon. Dispatcher owns every launch of a session (Stance item 8, docs/design.md; dispatcher/README.md).
2. A self-improving loop. It improves the work of the repository, and it runs on the self-hosted services of this repository (Stance item 9, docs/design.md).
3. Resilience by avenue count. Several independent paths reach the forge: the LAN, the tailnet with the subnet route, and the mirror (Stance item 6, docs/design.md; docs/adr/forge-naming-chain.md).
4. Everything that reaches the owner passed an agent review first. A queue of the owner holds only reviewed pull requests.
5. Agent-generated state joins the backup set as it appears: transcripts, memory, dispatcher state.
6. Dispatcher is security spine: it stays human-authored with agent assist.

## Purpose of the Services

Purpose of the topic: the factory loop and the sync run on the hardware of the owner, unattended, and the forge answers through more than one path. No spawner makes the host unusable: failure stays inside the sessions of the dev user, the host answers or resets, and the LAN keeps its internet path through the failover. Stance items 2 and 6 of docs/design.md state the criteria, and issue 267 states the goal of the resilience layers.

## Change the Services

Change the dispatcher:

1. Edit dispatcher.py or dispatcher.nix, and the README in the same commit.
2. Run `python3 modules/services/dispatcher/dispatcher-test.py` in the worktree when python3 is on the path. CI runs it on every pull request either way.

Add a syncthing folder: declare the folder and its devices in lib/syncthing.nix, and name the device IDs in the local.nix of each machine.

Change a resilience limit: edit the module of the layer, and cite the measured basis. Numbers of the incident: sixteen GiB of memory, no disk swap, about three GiB of standing stack outside the slice, so the caps leave about one GiB of headroom when the cap binds (issue 267). Re-measure the standing stack after a rebuild with free and systemd-cgtop, and lower the caps when the stack grows past four GiB.

Reach the forge over ssh: the route lives in docs/runbook.md, with the ssh layer of docs/secrets.md.
