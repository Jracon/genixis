# AGENTS.md - genixis Nix Configuration Repository

**Last updated:** 2026-10-20 | **Branch:** main

Declarative Nix flake monorepo: NixOS, macOS (nix-darwin), and Home Manager. Self-hosted media stack + productivity services via Podman OCI containers.

Origin is self-hosted Forgejo; mirrored to `github:jracon/genixis` (the URL used in README/rebuild commands, and by `.forgejo/workflows/update-flake.yaml` — see CI below).

> **Keep this file current.** Any change that adds, removes, or renames a host/output, flake input, `common/` file, module directory, container, or Home Manager user — or that changes or breaks a convention below — must update AGENTS.md (and README.md, if install/rebuild steps change) in the same commit. If code and this file disagree, fix whichever is wrong rather than working around it.

---

## STRUCTURE

```
genixis/
├── flake.nix                # Outputs: darwinConfigurations, formatter, homeConfigurations, nixosConfigurations
├── home.nix                  # Home Manager base (stateVersion, standalone homeDirectory fallback)
├── agenix-rules.nix           # agenix public keys
├── common/                    # Modules shared across hosts — see flake.nix's module lists for which file goes where
├── modules/
│   ├── hardware/               # cachyos-kernel, windows-dual-boot (desktop only)
│   ├── programs/cli/           # One .nix per CLI tool, loaded on every platform
│   ├── programs/darwin/        # macOS-only Home Manager extras
│   ├── programs/gui/           # GUI apps (macOS, and NixOS with local.gui = true)
│   ├── programs/nixos/         # NixOS-only Home Manager extras
│   ├── services/                # tailscale/, rclone-webdav.nix
│   └── virtualisation/
│       ├── podman.nix           # backend config + daily autoPrune
│       └── oci-containers/      # self-hosted services, one subdir per group
├── users/                       # optional per-user Home Manager overrides (users/<name>.nix, loaded if present)
└── disk-layouts/                # disko partitioning templates
```

Secrets: declare in `agenix-rules.nix`, consume via `config.age.secrets.*.path`.

## MODULE LOADING (flake.nix)

Hosts list their modules as plain paths. `expandModules` replaces each directory in a list with every `.nix` file beneath it (recursively); files and non-path modules (e.g. `agenix.nixosModules.default`) pass through unchanged. A mistyped path is an evaluation error. Adding a `.nix` file to a listed directory loads it automatically — keep non-module files (`.age`, `.yaml`, scripts) non-`.nix`.

**Outputs:** NixOS — `bare`, `media` (arr stack + downloaders), `services` (productivity/infra), `desktop` (dual-boot Windows gaming PC, Plasma, CachyOS kernel), `wsl` (NixOS-WSL), `disko` (install-time). Darwin — `m2pro-mbp`. Home Manager (standalone) — `jademeskill`, `nixos`, `root`.

NixOS hosts are built by `nixosConfiguration { homeUsers; roleModules; } [ <host module paths> ]`, wrapped as `desktopConfiguration`, `serverConfiguration` and `wslConfiguration`. For "which `common/*.nix` file applies to which host," read the module lists in `flake.nix` directly — they're the source of truth.

### Home Manager

Home Manager runs **as a NixOS/nix-darwin module** (`common/home-manager.nix`), so `nixos-rebuild`/`darwin-rebuild` applies it too. `useGlobalPkgs = true`, `useUserPackages = true`, `backupFileExtension = "backup"`.

- **Users per host:** every NixOS host manages `root`; `desktop` adds `jademeskill`, `wsl` adds `nixos`; Darwin manages `jademeskill`. Set via `homeUsers` in `flake.nix`. `common/nixos.nix` declares each non-root `homeUsers` entry as `isNormalUser` (merges with `/etc/nixos/configuration.nix`).
- **Program set** is chosen by platform in the `homeModules` function: Darwin → `cli`+`darwin`+`gui`; NixOS with `local.gui = true` → `cli`+`gui`+`nixos`; NixOS otherwise → `cli`+`nixos`. The standalone `homeConfigurations` reuse the same `homeModules`.
- **Standalone `homeConfigurations`** exist only for non-NixOS machines. Don't `rehome` on a NixOS/Darwin host — it would fight the system-managed generation.
- Because of `useGlobalPkgs`, **never set `nixpkgs.*` inside a Home Manager module** — it errors.

**Gotchas worth knowing before editing `common/`:**

- `base.nix` is loaded by every NixOS and Darwin host: empty `defaultPackages`, git, flakes, Nix GC/optimise, timezone. Anything universal and OS-level goes here.
- `homebrew.nix` adds `${homebrew.prefix}/bin` and `/sbin` to `environment.systemPath` at `mkOrder 1100` — after the Nix profiles, so Nix-installed tools shadow Homebrew ones.
- `nixpkgs.nix` holds `allowUnfree` and the `nix-vscode-extensions` overlay. It's loaded by every NixOS and Darwin host _and_ by standalone Home Manager (the option paths are identical), so it's the one place for nixpkgs config.
- `darwin.nix` uses `self.rev or self.dirtyRev or null` for `system.configurationRevision` — keep `self` in specialArgs. It also sets `users.users.<user>.home`, which the Home Manager module needs.
- `agenix.nix` loads on Darwin and servers; its Darwin identity path comes from `config.system.primaryUser` (no `user` arg on NixOS).
- `dummy-configuration.nix` exists only so builds/CI don't fail when no host config exists yet — never edit it.
- `llm-agents.nix` installs `claude-code` via `numtide/llm-agents.nix`; needs the `llm-agents` input in specialArgs.
- `wsl.nix` force-disables systemd-boot (overrides the dummy config) and leaves `wsl.defaultUser` to `/etc/nixos/configuration.nix`.
- Never put NixOS-only options in a file loaded on Darwin (check flake.nix's module list first).

## `modules/programs/cli/`

Shell is **fish**, not zsh (migrated — `zsh.nix` no longer exists, don't reintroduce it). One file per tool; a bare `enable = true` with no extra config goes in the `programs` block of that directory's `packages.nix` (`cli/packages.nix` for every platform, `nixos/packages.nix` for NixOS-only), not its own file. Fish integration is enabled once, via `home.shell.enableFishIntegration = true` in `fish.nix`, which is the default for every program's `enableFishIntegration` — don't set it per tool, and don't hand-wire integrations into `fish.nix`.

**Neovim** (`neovim.nix` + `neovim/lua/genixis/`): plugins, Tree-sitter grammars, language servers and formatters come from nixpkgs (`plugins`/`extraPackages`); the config is plain Lua in `neovim/`. The generated `init.lua` prepends `~/projects/genixis/modules/programs/cli/neovim` to the runtimepath when that checkout exists (edits apply on nvim restart, no rebuild), otherwise the store copy. No Mason or lazy.nvim — nothing is downloaded at runtime. Format Lua with `stylua` (config in `neovim/.stylua.toml`). Adding a language: its server/formatter in `extraPackages`, a `servers` entry in `lsp.lua`, a `formatters_by_ft` entry in `editing.lua`, and its grammar in `nvim-treesitter.withPlugins`. `nixd` gets option completion for this repo (Darwin, Home Manager, NixOS `media`) via `before_init` in `lsp.lua`.

**Fish custom functions** (`fish.nix`):

| Function                                      | Action                                                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `rebuild <target>` / `local-rebuild <target>` | `nixos-rebuild`/`darwin-rebuild` (includes Home Manager), from `github:jracon/genixis` / from local `.`                   |
| `rehome <target>` / `local-rehome <target>`   | standalone `home-manager switch`, remote / local — only defined in standalone configs (`!config.submoduleSupport.enable`) |

Aliases: `cat→bat`, `ls→eza`, `tmux→tmux new -As main`. `EDITOR` is `nvim` everywhere (`programs.neovim.defaultEditor`); VSCodium stays installed as a fallback GUI editor. On NixOS, fish auto-attaches to tmux session `main` on login (skipped on Darwin).

## `modules/programs/darwin/` and `modules/programs/nixos/`

- `darwin/default.nix` — enables `targets.darwin.copyApps` (and disables `linkApps`) so Home Manager `.app` bundles are real copies in `~/Applications/Home Manager Apps`, which Spotlight indexes. The Dock (`common/darwin.nix`) pins those copies, not `${pkgs.<app>}` store paths — otherwise Spotlight-launched apps show up as a second Dock entry.
- `nixos/packages.nix` — NixOS-only bare enables (lazydocker).

## `modules/virtualisation/oci-containers/`

Podman containers grouped by function, one subdir per group, wired into `nixosConfigurations` by listing the group's directory (or a flat file) in the host's module list in `flake.nix`. Directory names match their services 1:1 (`ls` a group to see what's in it) — `media-downloaders/`, `media-managers/`, `media-servers/` all load on `media`; `caddy/`, `continuwuity/`, `forgejo/`, `invidious/`, `mealie/`, `monica/`, `radicale/`, `vaultwarden/`, and the flat `languagetool.nix` all load on `services`.

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

Persistent data is always a bind mount under `/mnt/<service>/` (one subdirectory per mount when there are several, e.g. `/mnt/romm/mysql`, `/mnt/romm/redis-data`) — **no named Podman volumes**. Create every bind-mount directory in the activation script.

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

Gluetun is the VPN gateway. Deluge joins `gluetun-network` and depends on it (verified to exit via the VPN):

```nix
virtualisation.oci-containers.containers.my-downloader = {
  dependsOn = [ "gluetun" ];
  networks = [ "gluetun-network" ];
  # ...
};
```

Torrent clients must route through gluetun. `sabnzbd` (Usenet, TLS) and `shelfmark` currently do **not** join `gluetun-network`. Gluetun's secret lives at `./gluetun/environment.age` (subdir, not flat); its state is at `/mnt/gluetun`, which deluge also mounts read-only at `/pia` for the forwarded port.

### Secret patterns

- `environmentFiles` — inject env vars (most common)
- Volume-mount secret file — inject a config file: `"${config.age.secrets.foo.path}:/etc/service/config"`
- Custom ownership — e.g. Recyclarr and Radicale set `group`/`mode`/`owner` on the secret attr to match a non-root container user

### Notable per-service quirks

- **Jellyfin** uses `extraOptions = ["--network=host"]` (not `networks`) — required for mDNS/DLNA discovery. The only container that should do this; firewall rules are still required.
- **pool.nix** (media-servers) is the one non-container file in that dir — sets `boot.kernelPackages` for ZFS compatibility and imports the `media` ZFS pool with autoScrub.
- **romm** commits `./romm/config.yaml` directly (bind-mounted, not a secret — no sensitive values in it). Its `mariadb:latest` tag follows upstream's example compose, intentionally.
- **recyclarr** mounts its config from an agenix secret (`./recyclarr/config.age`, contains API keys); runs as `user = "1000:1000"` to match secret ownership.
- **invidious** copies SQL/init scripts from the pinned `invidious` flake input (`flake = false`), passed through NixOS specialArgs. Bump it with `nix flake update invidious`.
- **forgejo.nix** also runs the native `services.forgejo-runner` instance that executes this repo's CI.

### Activation script naming

`create_<service>_directory` / `create_<service>_directories` or `create_<service>-network` — underscores in the attr name, hyphens in the network name. Always assign to `.text`.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```

## `modules/services/`

- `tailscale/tailscale.nix` — `useNetworkd = true` + a `networkd-dispatcher` rule enabling `rx-udp-gro-forwarding` via `ethtool` (perf tuning for `useRoutingFeatures = "server"`/subnet routing). Auth via agenix OAuth client secret (`client_secret.age`) with `authKeyParameters.ephemeral = false` set explicitly (OAuth-generated keys default to ephemeral); advertises `tag:genixis` + a `/24` subnet route. `tailscale0` is a trusted firewall interface.
- `rclone-webdav.nix` — ad-hoc `rclone serve webdav` systemd service (serves `/mnt/media/games/saves/` on :8080). **Tailnet-only**: no firewall port is opened, so it's reachable only via the trusted `tailscale0` interface. Still unauthenticated (TODO comments for agenix-based htpasswd/remote config) — don't open its port publicly.

## CI (`.forgejo/workflows/update-flake.yaml`)

Daily (and on dispatch), on the self-hosted Forgejo runner: `nix fmt -- --ci` → `nix flake update` → `nix flake check --impure` → evaluate `darwinConfigurations.m2pro-mbp` and every `homeConfigurations` user (flake check skips both) → build `media` and `services` toplevels (desktop skipped — it would compile the CachyOS kernel) → commit `flake.lock` if changed. When adding a host, user, or Darwin config, add it to these steps.

## COMMITS

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>)!: <summary>`.

- **Summary:** lowercase, imperative, no trailing period, ≤ 72 characters for the whole subject line.
- **Types:**
  - `feat` — new capability: a service, program, host, user, option
  - `fix` — wrong or unsafe behaviour corrected
  - `refactor` — restructuring with no behaviour change (ideally identical derivations)
  - `style` — `nix fmt` / layout-only changes
  - `chore` — dependency and lock bumps, removals, housekeeping
  - `ci` — `.forgejo/workflows/`
  - `docs` — AGENTS.md, README, comments only
  - `revert`
- **Scope** (optional): the one thing touched — a host (`media`, `desktop`, `darwin`), service or container (`romm`, `caddy`, `tailscale`), program (`fish`, `nvim`), or area (`flake`, `home`, `common`, `containers`, `agenix`). Omit it when a commit spans several.
- **Breaking (`!` + `BREAKING CHANGE:` footer):** anything that needs a manual step on the next rebuild — data migration, re-login, file cleanup. The footer says what to do.
- **Body:** explain *why*, and anything not obvious from the diff. One topic per commit, and each commit should evaluate on its own.
- The CI bot's `chore: update flake inputs` already fits this standard and stays as is.

## CODE STYLE

**Formatting:** `nix fmt` (nixfmt-tree) — always before commit, never manually format. CI fails on unformatted files.

**Layout rules** — nixfmt preserves but doesn't enforce these, so follow them by hand:

- **Multi-line:** nested sets and non-empty lists always span multiple lines; empty ones are `{ }` / `[ ]`. Exception: a one-item list passed as a function argument stays inline (`lib.hm.dag.entryAfter [ "writeBoundary" ]`).
- **Ordering:** keys A–Z, case-insensitive, otherwise by character code (`-` before `_`, shorter prefix first). Single-line options and nested blocks sort together — never group by shape. Same for function args (`...` last) and `inherit` lists. If a prefix gets a second key, merge it into one block (`nix.settings.x` + `nix = { ... }` → one `nix` block).
- **`enable` / `inherit` first**, followed by a blank line when other keys follow.
- **Domain-order exceptions:** containers start with `image`, blank, `hostname`/`pull`/`user`, blank, then A–Z; flake inputs put `url` first; disko puts `type` first; starship puts `format`/`right_format` first; VSCodium language blocks (`"[python]"`) go last; flake `outputs` args put `self` first; `let` bindings are ordered by dependency.
- **Lists** sort A–Z too, except where order means something: numbers (and port strings) sort numerically by host port; container `volumes` sort by container path (keeps a parent mount before files mounted inside it); positional args (`ExecStart`) and the Dock's `persistent-apps` keep their order.
- **Blank lines:** one between top-level option paths; one between sibling entities (containers, systemd units, flake inputs); otherwise only to separate logical groups.
- **Quotes:** don't quote keys that are valid identifiers (`users.users.root`, not `users.users."root"`).

Files/directories: kebab-case (`tailscale.nix`, `media-servers`). Variables/functions: camelCase (`expandModules`, `homeModules`).

**Simple module:**

```nix
{
  config,
  pkgs,
  ...
}:

{
  services.tailscale.enable = true;
}
```

**With local (per-machine) variables:**

```nix
{
  local,
  ...
}:

let
  primaryDisk = builtins.elemAt local.disks 0;
in { ... }
```

## COMMANDS

```bash
nix fmt                                                          # Format all .nix files
nix fmt -- --ci                                                  # Check formatting (matches CI)
nix flake check --impure                                        # Validate (matches CI)
nixos-rebuild switch --impure --flake .#${ROLE}                  # Apply NixOS + Home Manager (local checkout)
sudo darwin-rebuild switch --flake .#${HOSTNAME}                 # Apply macOS + Home Manager (local checkout)
home-manager switch --impure --flake .#${USERNAME}                # Standalone Home Manager, non-NixOS only
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel   # Dry build
nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath   # Evaluate Darwin (flake check skips it)
nix repl .#nixosConfigurations.<host>.config                     # Debug interactively
nix flake update                                                 # Bump all inputs
```

The `rebuild`/`rehome` fish functions (above) do the same against `github:jracon/genixis` instead of `.`, for machines without a local checkout.

New files must be `git add`ed before the flake can see them.

## ANTI-PATTERNS

- Never commit `.age` secret files' plaintext — use `agenix` encryption.
- Never hardcode secrets in `.nix` files — use `age.secrets.*` (see Secret patterns above).
- Never manually format — always `nix fmt`.
- Never `pull = "always"` on a container — use `pull = "newer"`.
- Never omit firewall rules for an exposed container port, or expose a sidecar DB's port to the host.
- Never put multi-service orchestration in a flat `.nix` — give it a subdirectory.
- Never set `nixpkgs.config`/`nixpkgs.overlays` anywhere but `common/nixpkgs.nix`.
- Never fetch sources with unpinned `builtins.fetchGit`/`fetchTarball` — add a flake input (`flake = false` for non-flakes).
- Don't reintroduce zsh config — the shell is fish now.
- Data dirs always at `/mnt/<service>/`; shared media always at `/mnt/media/`. No named Podman volumes.

## NOTES

- Per-machine secrets/settings: `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS) — **not committed**. Shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; windows-efi-handle = "..."; }`.
- Editor is VSCodium (not VSCode — unfree/license issues), with `jeanp413.open-remote-ssh` (from the `nix-vscode-extensions` Open VSX set) standing in for the MS-locked `ms-vscode-remote.remote-ssh`.
