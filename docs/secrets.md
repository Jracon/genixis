# Secrets and keys

The agenix secrets, the two key channels, the ssh login and push keys, and the ssh route to the forge.

## Secrets

Declare each secret in `agenix-rules.nix`. Use it through `config.age.secrets.*.path`. Never inline a key.

Two key channels exist, and no key crosses them:

- **Host key.** One pair per host that consumes a system secret. The private half lives only in the system channel of that host: `/root/.ssh/genixis_host` on NixOS, `~/.ssh/genixis_host` on macOS. `common/agenix.nix` names the path. A host that declares no system secret holds no host key.
- **User key.** One pair per user. The private half lives at `~/.ssh/genixis_user` of that user. `ssh.nix` names the path. The same pair sits in every home of that user, also in the standalone homes. It decrypts only the two user secrets: `.ssh/config.age` and the plan token. The key of `nixos` is pending: until it exists, the two user secrets do not decrypt for that user, so a rebuild of `wsl` and a standalone `rehome nixos` fail.

The public halves are `.ssh/agenix/hosts/<host>.pub` and `.ssh/agenix/users/<user>.pub`. `agenix-rules.nix` reads them and maps each secret to the hosts that consume it. The module lists in `flake.nix` give the mapping.

agenix decrypts every secret of one layer as one unit. When one secret does not decrypt, the activation fails every secret of that host or user. So each secret must name a key of every host that consumes it. The standalone homes have no system level, so the two user secrets must name every user key.

## SSH logins

- Each machine has its own login key at `~/.ssh/id_ed25519`. Generate it on that machine. Never share it.
- Commit only the public half, as `.ssh/authorized/<machine>.pub`. A user of a host that is not a person commits its key as `.ssh/authorized/<host>-<user>.pub`, for example `services-dev.pub`.
- The login key of `dev` on `services` exists so the factory loop can reach other machines. Generate it like every machine key.
- `common/ssh.nix` authorizes every file in that directory for root and for each `homeUsers` entry.
- The public halves under `.ssh/agenix/` stay outside that directory. They are secrets keys, not login keys.
- Each machine that runs agent sessions holds one push key at `~/.ssh/claude-bot`, beside the login key. Generate it on that machine. Register its public half on the forge account `claude-bot` and on no other account. A push through this key acts as the account that holds it.
- Never commit the public half of the push key to `.ssh/authorized/`. That directory authorizes logins to machines. The push key is not a login key.

## NOTES

- `modules/programs/cli/ssh.nix` adds plain `Host` blocks for `desktop`, `media`, and `services`. Each block has only the login user. The short names resolve through MagicDNS on the tailnet. With Tailscale off, they resolve through the DNS of the router on the LAN. The router registers DHCP hostnames, with the search domain `localdomain`. So the repository commits no address.
- `modules/programs/cli/ssh-agent.nix` starts one ssh agent per user on Linux, through a systemd user service. The `AddKeysToAgent` setting in `ssh.nix` loads a key into the agent at the first use of the key. So the passphrase is typed once per login session. macOS runs its own agent through launchd, so the service stays off there. A second agent would split the environment in two.
- ssh reaches the forge through DNS, like every other consumer of the name.
  - The Forgejo block in `.ssh/config.age` sets `User git`, `Port 222`, and the identity files. It sets no `HostName`: the router DNS resolves the name, and the tailnet's split DNS reaches the router from off the LAN. The host key is public material: `ssh.nix` installs it beside the hand-managed `known_hosts` and lists both files in `UserKnownHostsFile`. The block holds no tailnet name any more.
  - A machine on the LAN pushes with no Tailscale. The roaming Mac pushes through the subnet route, so it runs the app. The servers and `desktop` run `tailscale/client.nix` too.
  - The reason was macOS. Local Network privacy credited a tmux server to the WezTerm that started it. After that WezTerm quit, macOS blocked the LAN connections of the tmux server and of every pane. The errors were "No route to host", or "Undefined error: 0" from the ssh of Apple. Tailnet addresses are not covered by this rule.
  - The same block affected other LAN traffic from tmux on the Mac. One example was the HTTPS fetch from Forgejo by `rebuild`, which then fell back to GitHub.
  - launchd now starts the tmux server on Darwin (see docs/tmux-darwin.md). So no WezTerm is the parent of the server, and the end of a WezTerm has no effect on it.
  - macOS does not automatically allow a launchd agent to use the local network. This exception is for launchd daemons only ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). The server needs the Local Network privilege. If macOS shows the alert, select Allow.
  - macOS identifies a program by its code signature, and Nix builds of tmux have ad-hoc signatures. After a tmux update, LAN access can stop until macOS gets the permission again.
  - The ssh path of the forge is a standing design. The probe from a pane of the launchd server passed on 2026-11-05. The reversal of 2026-11-06 on issue #166 made the LAN the primary transport, and the same record dropped the committed hosts pins: the repository owns no address, and DNS resolves the name on every network.
