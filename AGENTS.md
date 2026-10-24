# AGENTS.md - genixis Nix Configuration Repository

**Last updated:** 2026-10-21 | **Branch:** main

Declarative Nix flake monorepo: NixOS, macOS (nix-darwin), and Home Manager. Self-hosted media stack + productivity services via Podman OCI containers.

Origin is self-hosted Forgejo (`git+https://forgejo.local.jracon.xyz/jracon/genixis`, the URL used in README install commands; LAN-only); mirrored to `github:jracon/genixis` (the README's off-LAN fallback, and used by `.forgejo/workflows/update-flake.yaml` — see CI below).

> **Keep this file current.** Any change that adds, removes, or renames a host/output, flake input, `common/` file, module directory, container, or Home Manager user — or that changes or breaks a convention below — must update AGENTS.md (and README.md, if install/rebuild steps change) in the same commit. If code and this file disagree, fix whichever is wrong rather than working around it.

---

## STRUCTURE

```
genixis/
├── flake.nix                # Outputs: darwinConfigurations, formatter, homeConfigurations, nixosConfigurations
├── home.nix                  # Home Manager base (stateVersion, standalone homeDirectory fallback)
├── agenix-rules.nix           # agenix public keys
├── common/                    # Modules shared across hosts — see flake.nix's module lists for which file goes where
├── lib/                       # Non-module helpers that modules import (no host lists it, so expandModules never loads it)
│   └── syncthing.nix          # Syncthing devices + folders (shared by the NixOS and Home Manager modules)
├── modules/
│   ├── hardware/               # cachyos-kernel, windows-dual-boot (desktop only)
│   ├── programs/cli/           # One .nix per CLI tool, loaded on every platform
│   ├── programs/darwin/        # macOS-only Home Manager extras
│   ├── programs/gui/           # GUI apps (macOS, and NixOS with local.gui = true)
│   ├── programs/nixos/         # NixOS-only Home Manager extras
│   ├── services/                # syncthing.nix, tailscale/ (client.nix, server.nix), rclone-webdav.nix
│   └── virtualisation/
│       ├── podman.nix           # backend config + daily autoPrune
│       └── oci-containers/      # self-hosted services, one subdir per group
├── users/                       # optional per-user Home Manager overrides (users/<name>.nix, loaded if present)
└── disk-layouts/                # disko partitioning templates
```

Secrets: declare in `agenix-rules.nix`, consume via `config.age.secrets.*.path`. Every secret is encrypted to one shared key, `genixis_secrets`: its public half is `.ssh/genixis_secrets.pub` (read by `agenix-rules.nix`, not inlined), and each machine's system (`/root/.ssh/` on NixOS, `~/.ssh/` on macOS) and every Home Manager user (`~/.ssh/`, for `.ssh/config.age`) needs the private key.

SSH logins: each machine has its own login key at `~/.ssh/id_ed25519`, generated on that machine and never shared, and commits only its public half as `.ssh/authorized/<machine>.pub`. `common/ssh.nix` authorizes every file there for root and each `homeUsers` entry except `dev`. `genixis_secrets.pub` stays outside that directory: it's the secrets key, not a login key.

## MODULE LOADING (flake.nix)

Hosts list their modules as plain paths. `expandModules` replaces each directory in a list with every `.nix` file beneath it (recursively); files and non-path modules (e.g. `agenix.nixosModules.default`) pass through unchanged. A mistyped path is an evaluation error. Adding a `.nix` file to a listed directory loads it automatically — keep non-module files (`.age`, `.yaml`, scripts) non-`.nix`.

**Outputs:** NixOS — `bare`, `media` (arr stack + downloaders), `services` (productivity/infra), `desktop` (dual-boot Windows gaming PC, Plasma, CachyOS kernel), `wsl` (NixOS-WSL), `disko` (install-time). Darwin — `m2pro-mbp`. Home Manager (standalone) — `jademeskill`, `nixos`, `root`.

NixOS hosts are built by `nixosConfiguration { homeUsers; roleModules; } [ <host module paths> ]`, wrapped as `desktopConfiguration`, `serverConfiguration` and `wslConfiguration`. `nixosConfigurations` sets each host's `networking.hostName` to its output name (`mkDefault`, so `/etc/nixos/configuration.nix` can override it); `disko` is left out. For "which `common/*.nix` file applies to which host," read the module lists in `flake.nix` directly — they're the source of truth.

### Home Manager

Home Manager runs **as a NixOS/nix-darwin module** (`common/home-manager.nix`), so `nixos-rebuild`/`darwin-rebuild` applies it too. `useGlobalPkgs = true`, `useUserPackages = true`, `backupFileExtension = "backup"`.

- **Users per host:** every NixOS host manages `root`; `desktop` adds `jademeskill`, `services` adds `dev` (remote development; no SSH key yet, `devServerConfiguration` in `flake.nix`), `wsl` adds `nixos`; Darwin manages `jademeskill`. Set via `homeUsers` in `flake.nix`. `common/nixos.nix` declares each non-root `homeUsers` entry as `isNormalUser` (merges with `/etc/nixos/configuration.nix`).
- **Palette** is chosen per host: `nixosConfiguration` takes `palette` (default `violet`; `desktopConfiguration` passes `moss`), `homeModules` turns it into `genixis.palette.name`, and Darwin/standalone homes use the default. See Colour palette below.
- **Program set** is chosen by platform in the `homeModules` function: Darwin → `cli`+`darwin`+`gui`; NixOS with `local.gui = true` → `cli`+`gui`+`nixos`; NixOS otherwise → `cli`+`nixos`. The standalone `homeConfigurations` reuse the same `homeModules`.
- **Standalone `homeConfigurations`** exist only for non-NixOS machines. Don't `rehome` on a NixOS/Darwin host — it would fight the system-managed generation.
- Because of `useGlobalPkgs`, **never set `nixpkgs.*` inside a Home Manager module** — it errors.

**Gotchas worth knowing before editing `common/`:**

- `base.nix` is loaded by every NixOS and Darwin host: empty `defaultPackages`, git, flakes, Nix GC/optimise, timezone. Anything universal and OS-level goes here.
- `homebrew.nix` adds `${homebrew.prefix}/bin` and `/sbin` to `environment.systemPath` at `mkOrder 1100` — after the Nix profiles, so Nix-installed tools shadow Homebrew ones.
- `nixpkgs.nix` holds `allowUnfree` and the `nix-vscode-extensions` overlay. It's loaded by every NixOS and Darwin host _and_ by standalone Home Manager (the option paths are identical), so it's the one place for nixpkgs config.
- `darwin.nix` uses `self.rev or self.dirtyRev or null` for `system.configurationRevision` — keep `self` in specialArgs. It also sets `users.users.<user>.home`, which the Home Manager module needs.
- `agenix.nix` loads on Darwin and servers; its Darwin identity path comes from `config.system.primaryUser` (no `user` arg on NixOS).
- `gaming.nix` is desktop-only: Steam (with Remote Play/local transfer firewall rules, gamescope session), GameMode, 32-bit graphics. Playnite is Windows-only, so it lives on the Windows side of the dual boot.
- `dummy-configuration.nix` exists only so builds/CI don't fail when no host config exists yet — never edit it.
- `llm-agents.nix` installs `claude-code` via `numtide/llm-agents.nix`; needs the `llm-agents` input in specialArgs.
- `wsl.nix` force-disables systemd-boot (overrides the dummy config) and leaves `wsl.defaultUser` to `/etc/nixos/configuration.nix`.
- Never put NixOS-only options in a file loaded on Darwin (check flake.nix's module list first).

## Colour palette

Palettes live in their own flake, the `themes` input (on Forgejo as the public `jracon/themes`, fetched over HTTPS): `palettes.json` is the source of truth (`moss`, `violet`), and its `lib` generates theme files for any consumer (CSS, JSON, WezTerm, a neovim plugin). To change or add a colour, edit it there, then `nix flake update themes` here; don't copy hex into this repo.

This repo only chooses and applies. `modules/programs/cli/palette.nix` exposes `genixis.palette.name` (which palette; set per host, see Home Manager above) and `genixis.palette.colors` (`themes.lib.resolve name`: the palette plus `ansi.{dark,light}` and `signatureAnsi`). Real hex appears in only two places: WezTerm (`themes.lib.weztermSchemes`, picked by the OS appearance) and neovim (the `themes` plugin from `themes.lib.neovimPlugin`, `:colorscheme themes`, which reads `background` from the terminal and re-applies on `OptionSet background`). Every other terminal tool (tmux, starship, bat `ansi`, delta `ansi`, lazygit) names ANSI colours so it follows the active WezTerm scheme — don't hardcode hex in them.

## `modules/programs/cli/`

Shell is **fish**, not zsh (migrated — `zsh.nix` no longer exists, don't reintroduce it). One file per tool; a bare `enable = true` with no extra config goes in the `programs` block of that directory's `packages.nix` (`cli/packages.nix` for every platform, `nixos/packages.nix` for NixOS-only), not its own file. Fish integration is enabled once, via `home.shell.enableFishIntegration = true` in `fish.nix`, which is the default for every program's `enableFishIntegration` — don't set it per tool, and don't hand-wire integrations into `fish.nix`.

**Neovim** (`neovim.nix` + `neovim/lua/genixis/`): plugins, Tree-sitter grammars, language servers and formatters come from nixpkgs (`plugins`/`extraPackages`); the config is plain Lua in `neovim/`. The generated `init.lua` prepends the store copy of `neovim/` to the runtimepath, so Lua edits apply after a rebuild and an nvim restart. Never hardcode a checkout path to load it live. The colourscheme comes from the `themes` flake (see Colour palette), not tokyonight. No Mason or lazy.nvim — nothing is downloaded at runtime. Format Lua with `stylua` (config in `neovim/.stylua.toml`). Adding a language: its server/formatter in `extraPackages`, a `servers` entry in `lsp.lua`, a `formatters_by_ft` entry in `editing.lua`, and its grammar in `nvim-treesitter.withPlugins`. `nixd` gets option completion for this repo (Darwin, Home Manager, NixOS `media`) via `before_init` in `lsp.lua`.

**Fish custom functions** (`fish.nix`, defined via `programs.fish.functions`), all wrapping [nh](https://github.com/nix-community/nh), which shows a package diff before switching and elevates with sudo itself:

| Function                                      | Action                                                                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `rebuild <host>` / `local-rebuild <host>`     | `nh os switch --impure` / `nh darwin switch --impure` (includes Home Manager), from Forgejo (GitHub mirror if unreachable) / from local `.`  |
| `rehome <user>` / `local-rehome <user>`       | `nh home switch --impure`, remote / local — only defined in standalone configs (`!config.submoduleSupport.enable`)              |

`nh os` refuses to run as root, so the NixOS functions pass `--elevation-strategy none` when `fish_is_root_user` (the servers log in as root). `nix.gc` in `base.nix` still handles garbage collection — don't also enable `programs.nh.clean`.

**Plain-word commands** (`fish.nix`): fish abbreviations (`shellAbbrs`) that expand to the real command as you type — `b`→`y` (yazi), `dl`→`delta`, `g`→`z`, `iss`/`prs`/`prc`→`gh issue list`/`gh pr list`/`gh pr checkout`, `json`→`jq`, `lg`→`lazygit`, `l`→`fd`, `monitor`→`btm`, `r`→`bat`, `search`→`rg` — plus functions `e` (`nvim`, or its file picker with no args) and `cln` (`nh clean all --keep 5`). Platform-specific ones are gated on the tool actually existing, via `osConfig` (null in standalone), not on the platform: `ld`→`lazydocker` (`programs.lazydocker.enable`), `lgs <svc>`→`journalctl -fu podman-<svc>` (Podman hosts), `open`→`xdg-open` (Linux with `services.graphical-desktop.enable`). Prefer abbreviations over aliases; don't shadow `history`, `help`, `diff`, `git`, `top`, or macOS `open`.

**Projects** (`project`, a fish function in `project.nix`): a project directory holds `main/` (an ordinary clone on the default branch) and one git worktree per branch beside it, `<dir>/<branch>` with `/` turned into `-`; nothing lives inside a repo, and no path is hardcoded (`<dir>` resolves from the current directory). `project open [dir] [branch]` opens `main/` in an `ide` window titled `<dir>`, or the branch's worktree titled `<dir>: <branch>`, creating it first: an existing local branch is checked out, a remote-only one tracked, and a new one branched (`--no-track`) from `origin/<default>` after a 10-second `git fetch` (local main if that fails), so it includes PRs merged since main was last pulled. A missing `<dir>` asks before creating the project (`main/` with `git init` and an empty first commit, which worktrees need). For a plain repo it offers `project convert` (`never` records `project.convert = false` in the repo's local git config and stops asking); a repo left plain opens as it is, without branches. `<dir>/.worktreeinclude` (gitignore syntax, outside every repo so never committed) lists untracked files in `main/` to copy into new worktrees (copy-on-write where supported), with a leading `@` symlink, or with a leading `~` copy but discard on close without comparing (for files a build regenerates per branch). `project close [worktree]` refuses while a plain copy differs from `main/`, removes the copies, `~` discards and links, runs `git worktree remove` (which refuses on uncommitted work), deletes the branch only if it's merged into main or `origin/<default>`, then kills the worktree's `ide` window. Claude Code's memory lives in the project: `project open` starts `claude --settings '{"autoMemoryDirectory": "<dir>/.claude/memory"}'` (it's ignored in a committed `.claude/settings.json`, but a flag is honoured), shared by `main/` and every worktree and kept after `close`; transcripts stay under `~/.claude/projects/`. `project convert <repo>` moves a plain repo to `<repo>/main`, repairs its linked worktrees, moves Claude Code's memory for the old path into `<repo>/.claude/memory`, and renames its per-path transcript directory (`~/.claude/projects/<path, non-alphanumerics as ->`) to match. direnv is left alone: `direnv allow` each new worktree by hand.

**IDE layout** (`ide [dir] [title] [claude args...]`, a fish function in `fish.nix`): builds a tmux window named after the directory (or the title) with yazi on the left, nvim (started with `--listen`) over a shell in the middle, and `claude` (with any extra arguments, fish-escaped) on the right. Inside tmux it's a tab of the current session: built in place when the current window is a single pane, otherwise a new window, and a window already open on that directory (`@ide_dir`) is just selected. Outside tmux it creates (or reattaches to) a session named after the directory. `ide close`, run from any pane of an `ide` window, kills that window (and so its session, if it's the only one): it refuses while nvim has unsaved buffers (asked over the socket), and first swaps nvim back if an `ide-view` viewer is standing in for it, so nothing is left behind in the viewer's throwaway session. `ide reload` (same checks) picks up a rebuild in that window: it re-sources the tmux config, saves nvim's tabs with `mksession` (without `options`, which would restore the old runtimepath), quits it and starts the new nvim on the same socket from that session, and respawns the yazi pane; claude (possibly the caller) and the shell pane are left running. `ide` records the pane ids and nvim's socket as window options (`@ide_agent`, `@ide_dir`, `@ide_editor`, `@ide_files`, `@ide_shell`, `@ide_sock`), and `tmux.nix` hooks (`client-attached`, `client-resized`) run `ide-layout` to re-proportion them to the window (yazi 15% clamped to 24-40 columns, claude 30%, shell 20% of the height). The yazi, shell and claude panes get `IDE_NVIM_SOCK` and `IDE_EDITOR_PANE` in their environment (per pane, so several IDEs can share a session); yazi's `edit` opener (`ide-open`, in `yazi.nix`) sends files to that nvim and focuses its pane (each in a tab of its own via `genixis.ide.open` over `--remote-expr`, scheduled so the call returns at once; a file already open switches to its tab, and a blank fresh buffer is reused), starting a new `nvim --listen` there if the old one was quit (outside an `ide` session it opens nvim in a new tmux window); it must stay non-blocking, since a blocking opener stalls yazi for seconds. Yazi shows a single column with no status bar (`mgr.ratio = [0 1 0]`: no parent, no preview; dotfiles shown via `mgr.show_hidden`; the `git` plugin (`yaziPlugins.git`, with its two `prepend_fetchers`) marks git status at the right of each row, ignored files with a dark-grey sign, since yazi can't hide gitignored files; `initLua` overrides `Root:layout` to give the status row height 0; `h` goes up; Enter uses the `smart-enter` plugin so directories are entered, not sent to nvim); Shift+Enter in yazi runs `ide-view` on the hovered file (tmux rewrites it to Alt+Enter in yazi panes, because yazi can't see Shift+Enter under tmux): the viewer runs in a throwaway tmux session and is swapped into the editor pane's place (glow for markdown, bat otherwise), so Ctrl+arrows still work; `q` swaps nvim back, and `ide-open` does too before opening a file. Ctrl+0..9 switch nvim tabs (0 = the 10th; the tabline is numbered to match): in an `ide` window tmux takes them from any pane and runs `ide-tab`, which calls `genixis.ide.tab` over the socket and focuses the editor; elsewhere tmux passes them through to nvim's own maps. Ctrl+Tab / Ctrl+Shift+Tab (`C-Tab` / `C-BTab` to tmux; WezTerm's own tab bindings for them are disabled) do the same for the next/previous tab (`ide-tab <window> next|prev`, `genixis.ide.step`). tmux windows are tmux's default `prefix 0..9`. tmux sets the terminal title (`set-titles`): an `ide` window's name (`<dir>` or `<dir>: <branch>`), otherwise `<session>: <window>`. `<leader>x` closes a file and, when it's the only window of one of several tabs, the tab. `hidden` is off (with `confirm` on), so `:q` or `<leader>x` on a modified file asks to save right then, instead of leaving the changes in a hidden buffer that only surfaces when the file is reopened. `tmux.nix` binds `prefix g` to a lazygit popup and `prefix D` to a lazydocker popup (only where `programs.lazydocker.enable`).

Aliases are for drop-in replacements that keep the familiar name: `cat→bat`, and `ls`/`ll`/`la`/`lt`/`lla` from `programs.eza`'s integration. bat and eza use auto colour/icons so piped output stays plain — never set them to `always`. `tmux` is a function: bare `tmux` runs `tmux new -As main` (`ssh` instead when `SSH_CONNECTION` is set, so an ssh login doesn't join the local terminal's session), anything else passes through. `EDITOR` is `nvim` everywhere (`programs.neovim.defaultEditor`); VSCodium stays installed as a fallback GUI editor. On NixOS, fish auto-attaches on login by running bare `tmux` (skipped on Darwin). Inside tmux, fish binds Ctrl-D to `delete-char`, so it never exits the shell (use `exit`): WezTerm types Enter + Ctrl-D into a pane it closes (Cmd+Q), and the tmux client forwards them to the focused pane.

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
- **forgejo.nix** also runs the native `services.forgejo-runner` instance that executes this repo's CI. Its only label is `native:host`: jobs run directly on `services` as the runner's DynamicUser and build through the host's sandboxed nix-daemon (a `docker://` label would add the runner to the rootful `podman` group, and builds in a job container run unsandboxed). Tools a job needs go in its `hostPackages`.

### Activation script naming

`create_<service>_directory` / `create_<service>_directories` or `create_<service>-network` — underscores in the attr name, hyphens in the network name. Always assign to `.text`.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```

## `modules/services/`

- `tailscale/` — servers list the directory, `desktop` only `client.nix`. `client.nix` is what every tailnet member needs (`services.tailscale` + its firewall port); on its own it logs in once with `sudo tailscale up` and accepts no routes, enforced with `tailscale set --accept-routes=false` (the servers advertise the LAN it's already on, so accepting it would send replies to LAN peers out over the tailnet), and it's what lets `desktop` resolve the servers' MagicDNS names (see the ssh note under NOTES). `server.nix` adds `useNetworkd = true` + a `networkd-dispatcher` rule enabling `rx-udp-gro-forwarding` via `ethtool` (perf tuning for `useRoutingFeatures = "server"`/subnet routing). Auth via agenix OAuth client secret (`client_secret.age`) with `authKeyParameters.ephemeral = false` set explicitly (OAuth-generated keys default to ephemeral); advertises `tag:genixis` + a `/24` subnet route. `tailscale0` is a trusted firewall interface.
- `syncthing.nix` — NixOS `services.syncthing` (loaded on `media` and `services`; data under `/mnt/syncthing`, default ports opened, web UI left on localhost). The structure is declared once in `lib/syncthing.nix`: `devices` (hostnames) and `folders.<name>.devices.<hostname>.type` (`sendreceive`/`sendonly`/`receiveonly`, that device's own permission), optional `versioning`. **Device IDs are not committed**: each machine's uncommitted `local.nix` carries `syncthing-device-ids = { <hostname> = "<id>"; }` for its peers (a peer without one is skipped, so CI evaluates without them). **Device names are hostnames** (`networking.hostName`: the output name on NixOS, and `common/darwin.nix` sets it from `hostname`): a host syncs only the folders listing it, and a host not declared as a device syncs nothing. Folders land at `/mnt/syncthing/<name>` on servers and `~/Sync/<name>` on clients, where `modules/programs/cli/syncthing.nix` runs Home Manager's `services.syncthing` for non-root users (empty topology = disabled everywhere). Device keys are generated on first run, so IDs are read off each machine with `syncthing device-id`.
- `rclone-webdav.nix` — ad-hoc `rclone serve webdav` systemd service (serves `/mnt/media/games/saves/` on :8080). **Tailnet-only**: no firewall port is opened, so it's reachable only via the trusted `tailscale0` interface. Still unauthenticated (TODO comments for agenix-based htpasswd/remote config) — don't open its port publicly.

## CI (`.forgejo/workflows/update-flake.yaml`)

Daily (and on dispatch), on the self-hosted Forgejo runner (`runs-on: native`, see forgejo.nix above): `nix fmt -- --ci` → `nix flake update` → `nix flake check --impure` → evaluate `darwinConfigurations.m2pro-mbp` and every `homeConfigurations` user (flake check skips both) → build `media` and `services` toplevels (desktop skipped — it would compile the CachyOS kernel) → commit `flake.lock` if changed. When adding a host, user, or Darwin config, add it to these steps.

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

Files/directories: kebab-case (`rclone-webdav.nix`, `media-servers`). Variables/functions: camelCase (`expandModules`, `homeModules`).

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
sudo darwin-rebuild switch --impure --flake .#${HOSTNAME}        # Apply macOS + Home Manager (local checkout)
home-manager switch --impure --flake .#${USERNAME}                # Standalone Home Manager, non-NixOS only
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel   # Dry build
nix eval --raw .#darwinConfigurations.m2pro-mbp.system.drvPath   # Evaluate Darwin (flake check skips it)
nix repl .#nixosConfigurations.<host>.config                     # Debug interactively
nix flake update                                                 # Bump all inputs
```

The `rebuild`/`rehome` fish functions (above) do the same against `git+https://forgejo.local.jracon.xyz/jracon/genixis` instead of `.`, for machines without a local checkout. Forgejo is LAN-only, so when it doesn't answer within 3 seconds (e.g. WSL while the Windows host is on the work VPN) they fall back to the GitHub mirror, `git+https://github.com/jracon/genixis`, and override the `themes` input with its mirror `git+https://github.com/jracon/themes` at the locked revision. Use `git+https://`, never `github:` refs: those resolve through the rate-limited, unauthenticated GitHub API.

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

- Per-machine secrets/settings: `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS) — **not committed**. Shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; syncthing-device-ids = { <hostname> = "..."; }; windows-efi-handle = "..."; }`.
- `modules/programs/cli/ssh.nix` adds plain `Host` blocks for `desktop`, `media` and `services` (just the login user). The short names resolve via MagicDNS on the tailnet, or the router's DNS (it registers DHCP hostnames, search domain `localdomain`) on the LAN with Tailscale off, so no address is committed.
- ssh reaches Forgejo over Tailscale: the Forgejo block in `.ssh/config.age` sets `HostName` to `services`' MagicDNS name (encrypted, so the tailnet name stays out of the public mirror) and `HostKeyAlias` to the LAN name's known_hosts entry. So every machine that pushes over ssh must run Tailscale: the servers and `desktop` (`tailscale/client.nix`) do, and the Mac and Windows (for WSL) run the app. The reason is macOS: Local Network privacy credits a tmux server to the WezTerm that launched it and blocks its LAN connections once that WezTerm quits ("No route to host", or "Undefined error: 0" from Apple's ssh), and tailnet addresses aren't covered. Other LAN traffic from tmux on the Mac (e.g. `rebuild`'s HTTPS fetch from Forgejo, which then falls back to GitHub) is still affected.
- Editor is VSCodium (not VSCode — unfree/license issues), with `jeanp413.open-remote-ssh` (from the `nix-vscode-extensions` Open VSX set) standing in for the MS-locked `ms-vscode-remote.remote-ssh`.
