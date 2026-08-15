# AGENTS.md - genixis Nix Configuration Repository

**Generated:** 2026-07-30 | **Branch:** main

Declarative Nix flake monorepo: NixOS, macOS (nix-darwin), Home Manager, and one Arch/CachyOS box (system-manager). Self-hosted media stack + productivity services via Podman OCI containers.

Origin is self-hosted Forgejo; mirrored to `github:jracon/genixis` (the URL used in README/rebuild commands, and by `.forgejo/workflows/update-flake.yaml`, which runs `nix flake update` + `nix flake check --impure` daily and auto-commits `flake.lock`).

---

## STRUCTURE

```
genixis/
├── flake.nix                # Outputs: darwinConfigurations, homeConfigurations, nixosConfigurations, systemConfigs
├── home.nix                  # Home Manager base
├── secrets.nix                # agenix public keys
├── common/                    # Modules shared across hosts — see flake.nix's module lists for which file goes where
├── modules/
│   ├── programs/cli/          # One .nix per CLI tool, loaded on every platform
│   ├── programs/darwin/        # macOS-only Home Manager extras
│   ├── programs/gui/           # macOS-only GUI apps
│   ├── programs/nixos/         # NixOS-only Home Manager extras
│   ├── services/                # tailscale/, rclone-webdav.nix
│   └── virtualisation/
│       ├── podman.nix           # backend config + daily autoPrune
│       └── oci-containers/      # self-hosted services, one subdir per group
├── users/                       # per-user Home Manager overrides
└── disk-layouts/                # disko partitioning templates
```

Secrets: declare in `secrets.nix`, consume via `config.age.secrets.*.path`.

## MODULE LOADING (flake.nix)

`generateConfigModules` turns host config keys into file paths — e.g. `{ programs = ["cli"]; }` loads every `.nix` under `modules/programs/cli/`; a `"modules"` key resolves relative to the repo root instead of `./modules/<key>/`. Both exact files and whole directories work.

Home Manager's program set is chosen by platform, not passed per-user: Darwin → `cli`+`darwin`+`gui`; NixOS with `local.gui = true` → `cli`+`gui`+`nixos`; NixOS otherwise → `cli`+`nixos`.

**Outputs:** NixOS — `bare`, `media` (arr stack + downloaders), `services` (productivity/infra), `disko` (install-time). Darwin — `m2pro-mbp`. Home Manager — `jademeskill`, `root`. system-manager — `gaming` (**WIP, untouched for a while** — CachyOS box, only wires `common/system.nix`, no host-specific config yet; check with the user before building on it).

For "which `common/*.nix` file applies to which host," read the module list in the relevant `*Configuration` function in `flake.nix` directly — it's the source of truth and shorter than any table reproducing it here.

**Gotchas worth knowing before editing `common/`:**

- `darwin.nix` uses `self.rev or self.dirtyRev or null` for `system.configurationRevision` — keep `self` in specialArgs.
- `dummy-configuration.nix` exists only so disko builds don't fail when no host config exists yet — never edit it.
- `llm-agents.nix` (installs `claude-code`/`opencode`/`pi` via `numtide/llm-agents.nix`) needs the `llm-agents` input in specialArgs.
- Never put NixOS-only options in a file loaded on Darwin (check flake.nix's module list first).

## `modules/programs/cli/`

Shell is **fish**, not zsh (migrated — `zsh.nix` no longer exists, don't reintroduce it). One file per tool; a bare `enable = true` with no extra config belongs in `packages.nix`, not its own file. Tools with shell integration set `enableFishIntegration = true` rather than hand-wiring it into `fish.nix`.

**Fish custom functions** (`fish.nix`):

| Function                                      | Action                                                                          |
| --------------------------------------------- | ------------------------------------------------------------------------------- |
| `rebuild <target>` / `local-rebuild <target>` | `nixos-rebuild`/`darwin-rebuild`, from `github:jracon/genixis` / from local `.` |
| `rehome <target>` / `local-rehome <target>`   | `home-manager switch`, remote / local                                           |

Aliases: `cat→bat`, `ls→eza`, `tmux→tmux new -As main`. `EDITOR=code -w`. On NixOS, fish auto-attaches to tmux session `main` on login (skipped on Darwin).

## `modules/programs/darwin/` and `modules/programs/nixos/`

- `darwin/default.nix` — `makeSpotlightApps` activation script: mirrors Home Manager `.app` bundles into a Spotlight-indexable dir via `osacompile`, preserving icons.
- `nixos/lazydocker.nix` — installs lazydocker. General-purpose, not tied to the `gaming` host.

## `modules/virtualisation/oci-containers/`

Podman containers grouped by function, one subdir per group, wired into `nixosConfigurations` via the `virtualisation = [...]` list in `flake.nix`. Directory names match their services 1:1 (`ls` a group to see what's in it) — `media-downloaders/`, `media-managers/`, `media-servers/` all load on `media`; `caddy/`, `forgejo/`, `invidious/`, `mealie/`, `monica/`, `vaultwarden/`, and the flat `languagetool.nix` all load on `services`.

### Standard container pattern

```nix
{ config, pkgs, ... }:
{
  age.secrets.my_secret.file = ./secret.age;        # if secrets needed

  networking.firewall.allowedTCPPorts = [ 8080 ];    # ALWAYS add firewall rules

  system.activationScripts.create_my-service_directory.text = ''
    mkdir -p /mnt/my-service
  '';

  virtualisation.oci-containers.containers.my-service = {
    image = "repo/image:tag";
    hostname = "my-service";
    pull = "newer";                                   # always "newer", never "always"
    environmentFiles = [ config.age.secrets.my_secret.path ];
    ports = [ "8080:80" ];
    volumes = [ "/mnt/my-service:/data" ];
    environment.TZ = "America/Phoenix";
  };
}
```

### Multi-container pattern (isolated network)

When a service has a sidecar DB or companion:

```nix
system.activationScripts.create_foo-network.text = ''
  ${pkgs.podman}/bin/podman network create foo-network --ignore
'';
# Then in each container: networks = [ "foo-network" ]; dependsOn = [ "foo-db" ];
```

Examples: invidious (3 containers), romm (+ mariadb), monica (+ db), gamevault (+ postgres).

### VPN routing pattern (media-downloaders)

Gluetun is the network gateway for all traffic-generating downloaders — they join `gluetun-network` and depend on it:

```nix
virtualisation.oci-containers.containers.my-downloader = {
  dependsOn = [ "gluetun" ];
  networks = [ "gluetun-network" ];
  # ...
};
```

Never expose a downloader directly without routing through gluetun. Gluetun's secret lives at `./gluetun/environment.age` (subdir, not flat).

### Secret patterns

- `environmentFiles` — inject env vars (most common)
- Volume-mount secret file — inject a config file: `"${config.age.secrets.foo.path}:/etc/service/config"`
- Custom ownership — e.g. Recyclarr sets `group`/`mode`/`owner` on the secret attr to match a non-root container user

### Notable per-service quirks

- **Jellyfin** uses `extraOptions = ["--network=host"]` (not `networks`) — required for mDNS/DLNA discovery. The only container that should do this; firewall rules are still required.
- **pool.nix** (media-servers) is the one non-container file in that dir — sets `boot.kernelPackages` for ZFS compatibility and imports the `media` ZFS pool with autoScrub.
- **romm** commits `./romm/config.yaml` directly (bind-mounted, not a secret — no sensitive values in it).
- **recyclarr** mounts its config from an agenix secret (`./recyclarr/config.age`, contains API keys); runs as `user = "1000:1000"` to match secret ownership.

### Activation script naming

`create_<service>_directory` or `create_<service>-network` — underscores in the attr name, hyphens in the network name.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```

## `modules/services/`

- `tailscale/tailscale.nix` — `useNetworkd = true` + a `networkd-dispatcher` rule enabling `rx-udp-gro-forwarding` via `ethtool` (perf tuning for `useRoutingFeatures = "server"`/subnet routing). Auth via agenix (`client_secret.age`); advertises `tag:genixis` + a `/24` subnet route.
- `rclone-webdav.nix` — ad-hoc `rclone serve webdav` systemd service (serves `/mnt/media/games/saves/`). Has TODO comments for agenix-based htpasswd/remote config — **currently unauthenticated**.

## CODE STYLE

**Formatting:** `nix fmt` (nixfmt) — always before commit, never manually format.

Files/directories: kebab-case (`tailscale.nix`, `media-servers`). Variables/functions: camelCase (`generateConfigModules`, `containerNames`).

**Simple module:**

```nix
{ config, pkgs, ... }:
{
  services.tailscale.enable = true;
}
```

**With local (per-machine) variables:**

```nix
{ local, ... }:
let
  primaryDisk = builtins.elemAt local.disks 0;
in { ... }
```

## COMMANDS

```bash
nix fmt                                                          # Format all .nix files
nix flake check --impure                                        # Validate (matches CI)
nixos-rebuild switch --impure --flake .#${ROLE}                  # Apply NixOS (local checkout)
sudo darwin-rebuild switch --flake .#${HOSTNAME}                 # Apply macOS (local checkout)
home-manager switch --impure --flake .#${USERNAME}                # Apply Home Manager (local checkout)
nix run 'github:numtide/system-manager' -- switch --flake .#gaming --sudo  # Apply system-manager
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel   # Dry build
nix repl .#nixosConfigurations.<host>.config                     # Debug interactively
nix flake update                                                 # Bump all inputs
```

The `rebuild`/`rehome` fish functions (above) do the same against `github:jracon/genixis` instead of `.`, for machines without a local checkout.

## ANTI-PATTERNS

- Never commit `.age` secret files' plaintext — use `agenix` encryption.
- Never hardcode secrets in `.nix` files — use `age.secrets.*` (see Secret patterns above).
- Never manually format — always `nix fmt`.
- Never `pull = "always"` on a container — use `pull = "newer"`.
- Never omit firewall rules for an exposed container port, or expose a sidecar DB's port to the host.
- Never put multi-service orchestration in a flat `.nix` — give it a subdirectory.
- Never add `nixpkgs.config.allowUnfree = true` globally — only in `users/*.nix`.
- Don't reintroduce zsh config — the shell is fish now.
- Data dirs always at `/mnt/<service>/`; shared media always at `/mnt/media/`.

## NOTES

- Per-machine secrets/settings: `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS) — **not committed**. Shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; }`.
- Editor is VSCodium (not VSCode — unfree/license issues), with `jeanp413.open-remote-ssh` (from the `nix-vscode-extensions` Open VSX set) standing in for the MS-locked `ms-vscode-remote.remote-ssh`.
