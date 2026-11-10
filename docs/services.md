# The services modules

The services of `modules/services/`: the dispatcher loop, tailscale, syncthing, rclone-webdav, and reticulum.

## `modules/services/`

### `dispatcher/` — the factory loop

The webhook receiver and the dispatcher of issue #74 phase 4 (issue #83). Only `services` loads the directory. The units run as systemd **user** services of `dev`, which lingers, so they start at boot.

- The receiver binds to the Podman bridge gateway (10.88.0.1:8741). Container traffic to the gateway enters the input chain of the host, so the module opens the port on the bridge interface alone (`podman0`). A poll timer on `tea` and a cursor file is the documented fallback. Read `modules/services/dispatcher/README.md` before you change anything here. It holds the event rules, the state files, the fallback switch, and the machine decisions.
- The module stays off until `webhook.age` exists. The owner creates that secret with `agenix -e`. It is a system secret of `services`, owned by `dev`, because the receiver runs as a user service of `dev`.
- The worker and reviewer roles of the loop are procedures of the `factory` skill. The dispatcher starts each leg through the same `project spawn --headless` CLI that the owner could type.
- This directory is security spine under standing principle 7 of issue #74. Review every change line by line.

### `tailscale/`

- Servers list the directory. `desktop` lists only `client.nix`.
- `client.nix` is what every tailnet member needs: `services.tailscale` and its firewall port.
  - On its own, it logs in once with `sudo tailscale up` and accepts no routes. `tailscale set --accept-routes=false` enforces this. The servers advertise the LAN that the client is already on. If the client accepted the routes, it would send replies to LAN peers out over the tailnet.
  - It lets `desktop` resolve the MagicDNS names of the servers (see the ssh note in docs/secrets.md).
- The Mac is the one client that accepts the subnet routes. It runs the App Store app, which `common/homebrew.nix` installs; no Nix module manages it. The app setting "Use Tailscale Subnets" is on, and the flake cannot manage it, so a reinstall needs the toggle again. At home, the connected route wins, so the LAN stays direct. Off the LAN, the subnet route carries the LAN. The NixOS clients keep declining routes.
- The tailnet resolves the domain `local.jracon.xyz` through split DNS: it delegates the domain to the router, so names under it resolve wherever Tailscale runs (issue #166). The coordination server sends this configuration, the admin console holds it, and the flake does not manage it. Read the state of a node with `tailscale dns status`.
- `server.nix` adds `useNetworkd = true` and a `networkd-dispatcher` rule. The rule enables `rx-udp-gro-forwarding` through `ethtool`. This is a performance tuning for `useRoutingFeatures = "server"` and subnet routing.
- Authentication uses an agenix OAuth client secret (`client_secret.age`). The config sets `authKeyParameters.ephemeral = false` explicitly, because OAuth-generated keys are ephemeral by default.
- The server advertises `tag:genixis` and a `/24` subnet route. `tailscale0` is a trusted firewall interface.

### `syncthing.nix`

This is the NixOS `services.syncthing`. `media` and `services` load it. Data is under `/mnt/syncthing`. The default ports are open. The web UI stays on localhost.

`lib/syncthing.nix` declares the structure once:

- `devices` lists hostnames.
- `folders.<name>.devices.<hostname>.type` is the permission of that device: `sendreceive`, `sendonly`, or `receiveonly`.
- `versioning` is optional.

Rules:

- **The repository does not commit device IDs.** The uncommitted `local.nix` of each machine carries `syncthing-device-ids = { <hostname> = "<id>"; }` for its peers. A peer without an ID is skipped, so CI evaluates without the IDs.
- **Device names are hostnames** (`networking.hostName`). On NixOS this is the output name. On Darwin, `common/darwin.nix` sets it from `hostname`.
- A host syncs only the folders that list it. A host that is not declared as a device syncs nothing.
- Folders land at `/mnt/syncthing/<name>` on servers and at `~/Sync/<name>` on clients.
- On clients, `modules/programs/cli/syncthing.nix` runs the Home Manager `services.syncthing` for non-root users. An empty topology disables it everywhere.
- Syncthing generates device keys on first run. Read the IDs from each machine with `syncthing device-id`.

### `rclone-webdav.nix`

This is an ad-hoc `rclone serve webdav` systemd service. It serves `/mnt/media/games/saves/` on :8080.

- It is **tailnet-only**. It opens no firewall port, so only the trusted `tailscale0` interface reaches it.
- It is still unauthenticated. TODO comments mention agenix-based htpasswd and remote config.
- Do not open its port to the public.

### `reticulum.nix`

This is the NixOS `services.rnsd`, the daemon of the Reticulum mesh network stack (issue #233). `media` and `services` load it.

- Each node is an AutoInterface node. It discovers peers through UDP multicast on the LAN. `openMulticastPorts` passes the ports 27916 and 42671 through the firewall.
- The settings state the scope of the phase: `enable_transport` stays off, and the one interface section `interfaces.auto` carries the peer discovery. Transport mode, a TCP interface on the tailnet, and messaging stay out until two nodes see each other and a follow-up issue asks for them (issue #233).
- The NixOS module copies the generated config into `/var/lib/rnsd` on each start, so the flake owns the daemon config. An empty `settings` makes rnsd write its own config on first start and keep it.
- The daemon runs under a dynamic user. It keeps its state and its generated identity under `/var/lib/rnsd`. The repository commits no identity.
- The CLI tools (`rnstatus`, `rnpath`, `rnprobe`, `rncp`, `rnid`, `rnsh`, `rnx`, `rngit`, `git-remote-rns`) come from `pkgs.rns` in `modules/programs/cli/packages.nix`, so every Home Manager user on every platform has them. Each user holds one instance: the first tool that runs starts it, and the others join it over a local socket. A user instance and the daemon hold separate identities, because each reads its own config directory.
- The module installs udev rules that link RNode radio devices to `/dev/rnode`. The fleet holds no RNode, so the rules match no device.

## NOTES

- **Background sessions and the LAN (issue #122).** macOS Local Network privacy gates a connection to a LAN address per process chain. The gate binds a background session only when its chain reaches no granted ancestor:
  - Every background session runs under a Claude Code daemon host. The parent of the daemon host varies with where the daemon host was started. When launchd starts the daemon host at boot, no grant covers the chain. When a session inside tmux starts the daemon host, the background sessions under it inherit the grant of the tmux server (issue #289). When macOS holds no grant for a program in the chain, macOS refuses its LAN connection at once with `no route to host`.
  - The launchd tmux server holds a grant that covers its panes. A test on 2026-11-04 built one program fresh. macOS held no grant for it. The program connected from a tmux pane. macOS refused it from a background session, because the daemon host of that day had launchd as its parent. The pane success and the refusal remain the proof of the per-chain gate.
  - A probe of a background session names its chain, the parent of its daemon host, before it reads the reachability as evidence. The reachability alone does not show the state of the gate.
  - The tailnet is outside this gate. The LAN is not. The repository maps no forge name. The router DNS resolves it, and the tailnet's split DNS delegates the domain to the router. The name resolves wherever Tailscale runs. An interactive session on the Mac reaches the address through a grant or the macOS alert. A background session reaches the address only when its chain inherits a grant. Nothing in this repository pins the parent of the daemon host. For this reason, no headless leg runs on Darwin. Run headless legs on `services`, where no gate exists.
  - A tool with a grant works in a background session until a rebuild gives the tool a new ad-hoc signature. macOS then treats the tool as new (see the tmux notes in docs/secrets.md).
  - Treat `no route to host` to a LAN address in a background session as this gate. Other chains still reach the LAN, so do not treat the error as a network outage.
