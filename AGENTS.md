# AGENTS.md - genixis Nix Configuration Repository

**Last updated:** 2026-10-21 | **Branch:** main

A declarative Nix flake monorepo. It configures NixOS, macOS (nix-darwin), and Home Manager, and runs a self-hosted media stack and productivity services in Podman OCI containers.

The origin is a self-hosted Forgejo server (`git+https://forgejo.local.jracon.xyz/jracon/genixis`), reachable on the LAN only. The README install commands use this URL. The origin is mirrored to `github:jracon/genixis`. The README uses the mirror as its off-LAN fallback, and so does `.forgejo/workflows/update-flake.yaml` (see CI below).

> **Keep this file current.** Update AGENTS.md in the same commit when a change does one of these:
>
> - It adds, removes, or renames a host, an output, a flake input, a `common/` file, a module directory, a container, or a Home Manager user.
> - It changes or breaks a convention below.
>
> Update README.md in the same commit if install or rebuild steps change. If the code and this file disagree, fix whichever is wrong. Do not work around the disagreement.
>
> **Writing rules.** Write every change to this file in Simplified Technical English (ASD-STE100). Use short sentences, active voice, and one word for one meaning. Put one instruction in each sentence. The text must also read fluently. Do not use sentence fragments or long chains of clauses. Use the `asd-ste100` skill when you write or rewrite a section.

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

### Secrets

Declare each secret in `agenix-rules.nix`. Use it through `config.age.secrets.*.path`.

Every secret is encrypted to one shared key, `genixis_secrets`. Its public half is `.ssh/genixis_secrets.pub`, which `agenix-rules.nix` reads. Do not inline the key. The private key must be in:

- Each machine's system: `/root/.ssh/` on NixOS, `~/.ssh/` on macOS.
- Every Home Manager user: `~/.ssh/`, for `.ssh/config.age`.

### SSH logins

- Each machine has its own login key at `~/.ssh/id_ed25519`. Generate it on that machine. Never share it.
- Commit only the public half, as `.ssh/authorized/<machine>.pub`.
- `common/ssh.nix` authorizes every file in that directory for root and for each `homeUsers` entry except `dev`.
- `genixis_secrets.pub` stays outside that directory. It is the secrets key, not a login key.

## MODULE LOADING (flake.nix)

Hosts list their modules as plain paths. `expandModules` replaces each directory in a list with every `.nix` file below it (recursively). Files and non-path modules (for example `agenix.nixosModules.default`) pass through unchanged. A mistyped path causes an evaluation error. A `.nix` file added to a listed directory loads automatically, so keep non-module files (`.age`, `.yaml`, scripts) non-`.nix`.

**Outputs:**

- NixOS: `bare`, `media` (arr stack and downloaders), `services` (productivity and infrastructure), `desktop` (dual-boot Windows gaming PC, Plasma, CachyOS kernel), `wsl` (NixOS-WSL), `disko` (install-time).
- Darwin: `m2pro-mbp`.
- Home Manager (standalone): `jademeskill`, `nixos`, `root`.

`nixosConfiguration { homeUsers; roleModules; } [ <host module paths> ]` builds the NixOS hosts. The wrappers are `desktopConfiguration`, `serverConfiguration`, and `wslConfiguration`. `nixosConfigurations` sets each host's `networking.hostName` to its output name with `mkDefault`, so `/etc/nixos/configuration.nix` can override it. `disko` is left out.

To learn which `common/*.nix` file applies to which host, read the module lists in `flake.nix`. They are the source of truth.

### Home Manager

Home Manager runs **as a NixOS/nix-darwin module** (`common/home-manager.nix`), so `nixos-rebuild` and `darwin-rebuild` apply it too. The settings are `useGlobalPkgs = true`, `useUserPackages = true`, and `backupFileExtension = "backup"`.

- **Users per host:** `homeUsers` in `flake.nix` sets them.
  - Every NixOS host manages `root`. `desktop` adds `jademeskill`. `wsl` adds `nixos`. Darwin manages `jademeskill`.
  - `services` adds `dev` (remote development, no SSH key yet, `devServerConfiguration` in `flake.nix`).
  - `common/nixos.nix` declares each non-root `homeUsers` entry as `isNormalUser`. This merges with `/etc/nixos/configuration.nix`.
- **Palette:** each host chooses its own. `nixosConfiguration` takes `palette` (default `violet`; `desktopConfiguration` passes `moss`). `homeModules` turns it into `genixis.palette.name`. Darwin and standalone homes use the default. See Colour palette below.
- **Program set:** the `homeModules` function chooses it by platform. The standalone `homeConfigurations` reuse the same `homeModules`.
  - Darwin: `cli` + `darwin` + `gui`.
  - NixOS with `local.gui = true`: `cli` + `gui` + `nixos`.
  - NixOS otherwise: `cli` + `nixos`.
- **Standalone `homeConfigurations`** exist only for non-NixOS machines. Do not run `rehome` on a NixOS or Darwin host. It would fight the generation that the system manages.
- `useGlobalPkgs` is on. **Never set `nixpkgs.*` inside a Home Manager module.** It causes an error.

**Gotchas to know before you edit `common/`:**

- Every NixOS and Darwin host loads `base.nix`. It sets empty `defaultPackages`, git, flakes, Nix GC and optimise, and the timezone. Put anything universal and OS-level here.
- `homebrew.nix` adds `${homebrew.prefix}/bin` and `/sbin` to `environment.systemPath` at `mkOrder 1100`. This is after the Nix profiles, so Nix-installed tools shadow Homebrew tools.
- `nixpkgs.nix` holds `allowUnfree` and the `nix-vscode-extensions` overlay. Every NixOS and Darwin host loads it. Standalone Home Manager loads it too, because the option paths are identical. It is the one place for nixpkgs config.
- `darwin.nix` uses `self.rev or self.dirtyRev or null` for `system.configurationRevision`. Keep `self` in specialArgs. The file also sets `users.users.<user>.home`, which the Home Manager module needs.
- `agenix.nix` loads on Darwin and on servers. Its Darwin identity path comes from `config.system.primaryUser`. NixOS has no `user` argument.
- `gaming.nix` is for `desktop` only. It sets up Steam (with Remote Play and local transfer firewall rules, and a gamescope session), GameMode, and 32-bit graphics. Playnite runs on Windows only, so it lives on the Windows side of the dual boot.
- `dummy-configuration.nix` exists only so that builds and CI do not fail when no host config exists yet. Never edit it.
- `llm-agents.nix` installs `claude-code` from `numtide/llm-agents.nix`. It needs the `llm-agents` input in specialArgs.
- `wsl.nix` force-disables systemd-boot (this overrides the dummy config). It leaves `wsl.defaultUser` to `/etc/nixos/configuration.nix`.
- Never put NixOS-only options in a file that Darwin loads. Check the module list in `flake.nix` first.

## Colour palette

Palettes live in their own flake, the `themes` input. It is the public Forgejo repository `jracon/themes`, fetched over HTTPS.

- `palettes.json` is the source of truth. It has the palettes `moss` and `violet`.
- Its `lib` generates theme files for any consumer (CSS, JSON, WezTerm, a neovim plugin).
- To change or add a colour, edit it in `themes`. Then run `nix flake update themes` here. Do not copy hex values into this repository.

This repository only chooses and applies palettes. `modules/programs/cli/palette.nix` exposes these options:

- `genixis.palette.name` is the palette name. Each host sets it (see Home Manager above).
- `genixis.palette.colors` is `themes.lib.resolve name`. It holds the palette plus `ansi.{dark,light}` and `signatureAnsi`.

Real hex appears in two places only:

- WezTerm uses `themes.lib.weztermSchemes`, picked by the OS appearance.
- Neovim uses the `themes` plugin from `themes.lib.neovimPlugin` (`:colorscheme themes`). The plugin reads `background` from the terminal and re-applies on `OptionSet background`.

Every other terminal tool names ANSI colours, so it follows the active WezTerm scheme: tmux, starship, bat `ansi`, delta `ansi`, and lazygit. Do not hardcode hex in them.

## `modules/programs/cli/`

The shell is **fish**, not zsh. `zsh.nix` no longer exists. Do not reintroduce it.

Each tool has one file. A bare `enable = true` with no extra config goes in the `programs` block of the `packages.nix` in that directory, not in its own file. Use `cli/packages.nix` for every platform and `nixos/packages.nix` for NixOS only.

Fish integration is on once, through `home.shell.enableFishIntegration = true` in `fish.nix`. This is the default for the `enableFishIntegration` option of every program. Do not set it per tool. Do not hand-wire integrations into `fish.nix`.

### Neovim

Files: `neovim.nix` and `neovim/lua/genixis/`.

- Plugins, Tree-sitter grammars, language servers, and formatters come from nixpkgs (`plugins` and `extraPackages`). The config is plain Lua in `neovim/`.
- The generated `init.lua` prepends the store copy of `neovim/` to the runtimepath. Lua edits take effect after a rebuild and an nvim restart. Never hardcode a checkout path to load the config live.
- The colourscheme comes from the `themes` flake (see Colour palette), not tokyonight.
- There is no Mason and no lazy.nvim. Nothing downloads at runtime.
- Format Lua with `stylua`. The config is in `neovim/.stylua.toml`.
- To add a language:
  1. Add its server or formatter to `extraPackages`.
  2. Add a `servers` entry in `lsp.lua`.
  3. Add a `formatters_by_ft` entry in `editing.lua`.
  4. Add its grammar to `nvim-treesitter.withPlugins`.
- `nixd` gets option completion for this repository (Darwin, Home Manager, NixOS `media`) through `before_init` in `lsp.lua`.

### Fish custom functions

`fish.nix` defines these functions through `programs.fish.functions`. All of them wrap [nh](https://github.com/nix-community/nh). nh shows a package diff before it switches. It elevates with sudo by itself.

| Function                                      | Action                                                                                                                         |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `rebuild <host>` / `local-rebuild <host>`     | `nh os switch --impure` / `nh darwin switch --impure` (includes Home Manager), from Forgejo (GitHub mirror if unreachable) / from local `.`  |
| `rehome <user>` / `local-rehome <user>`       | `nh home switch --impure`, remote / local — only defined in standalone configs (`!config.submoduleSupport.enable`)              |

`nh os` refuses to run as root. So the NixOS functions pass `--elevation-strategy none` when `fish_is_root_user` is true. The servers log in as root.

`nix.gc` in `base.nix` already handles garbage collection. Do not also enable `programs.nh.clean`.

### Plain-word commands

These are in `fish.nix`. Fish abbreviations (`shellAbbrs`) expand to the real command as you type:

- `b` → `y` (yazi), `dl` → `delta`, `g` → `z`, `json` → `jq`, `lg` → `lazygit`, `l` → `fd`, `monitor` → `btm`, `r` → `bat`, `search` → `rg`
- `iss` → `gh issue list`, `prs` → `gh pr list`, `prc` → `gh pr checkout`

Two functions also exist:

- `e` runs `nvim`, or its file picker when you give no arguments.
- `cln` runs `nh clean all --keep 5`.

Some commands are on only when the tool exists. The check uses `osConfig` (null in standalone), not the platform:

- `ld` → `lazydocker` (`programs.lazydocker.enable`).
- `lgs <svc>` → `journalctl -fu podman-<svc>` (Podman hosts).
- `open` → `xdg-open` (Linux with `services.graphical-desktop.enable`).

Prefer abbreviations to aliases. Do not shadow `history`, `help`, `diff`, `git`, `top`, or the macOS `open`.

### Projects (`project`)

`project` is a fish function in `project.nix`.

**Layout.** A project directory holds `main/` (an ordinary clone on the default branch) and one git worktree for each branch, next to `main/`, at `<dir>/<branch>`. Each `/` in the branch name becomes `-`. Nothing lives inside a repository. No path is hardcoded. `<dir>` resolves from the current directory.

**`project open [dir] [branch]`**

- With no branch, it opens `main/` in an `ide` window titled `<dir>`.
- With a branch, it opens that worktree in an `ide` window titled `<dir>: <branch>`, and creates the worktree first when needed.
- Opening `main/` or an existing worktree starts a silent background `git pull --ff-only` there.
- To create a worktree:
  - An existing local branch is checked out.
  - A remote-only branch is tracked.
  - A new branch comes from `origin/<default>` with `--no-track`, after a `git fetch` with a 10-second limit. If the fetch fails, the branch comes from local main. The fetch makes the new branch include PRs merged since main was last pulled.
- If `<dir>` does not exist, the command asks before it creates the project: `main/` with `git init` and an empty first commit (worktrees need that commit).
- For a plain repo, the command offers `project convert`. The answer `never` records `project.convert = false` in the local git config of the repo and stops the questions. A repo left plain opens as it is, without branches.

**`.worktreeinclude`**

- `<dir>/.worktreeinclude` uses gitignore syntax. It is outside every repo, so it is never committed.
- It lists untracked files in `main/` to copy into new worktrees. The copy is copy-on-write where the file system supports it.
- A leading `@` makes a symlink instead of a copy.
- A leading `~` makes a copy that `project close` discards without a comparison. Use it for files that a build regenerates for each branch.

**`project close [worktree]`**

1. It refuses while a plain copy differs from `main/`.
2. It removes the copies, discards the `~` files, and removes the links.
3. It runs `git worktree remove`, which refuses when uncommitted work exists.
4. It deletes the branch only if the branch is merged into main or `origin/<default>`.
5. It kills the `ide` window of the worktree.

**Claude Code memory.** The memory lives in the project. `project open` starts `claude --settings '{"autoMemoryDirectory": "<dir>/.claude/memory"}'`. A committed `.claude/settings.json` ignores this setting, but a flag is honoured. `main/` and every worktree share this memory, and it stays after `close`. Transcripts stay under `~/.claude/projects/`.

**`project convert <repo>`**

- It moves a plain repo to `<repo>/main` and repairs the linked worktrees of the repo.
- It moves the Claude Code memory for the old path into `<repo>/.claude/memory`.
- It renames the per-path transcript directory to match. The directory is `~/.claude/projects/<path, non-alphanumerics as ->`.

**direnv.** The project commands leave direnv alone. Run `direnv allow` by hand in each new worktree.

### IDE layout (`ide`)

`ide [dir] [title] [claude args...]` is a fish function in `fish.nix`. It builds a tmux window named after the directory (or after the title).

**Panes:** yazi on the left; nvim (started with `--listen`) over a shell in the middle; `claude` on the right, with any extra arguments (fish-escaped).

**Where the window goes:**

- Inside tmux, the window is a tab of the current session. If the current window is a single pane, `ide` builds the layout in place. Otherwise it makes a new window. A window already open on that directory (`@ide_dir`) is only selected.
- Outside tmux, `ide` creates a session named after the directory, or reattaches to it.

**`ide close`.** Run it from any pane of an `ide` window. It kills that window, and the session too if that window is the only one.

- It refuses while nvim has unsaved buffers. It asks nvim over the socket.
- If an `ide-view` viewer stands in for nvim, it first swaps nvim back. This leaves nothing in the throwaway session of the viewer.

**`ide reload`.** It does the same checks as `ide close`. It picks up a rebuild in that window:

1. It re-sources the tmux config.
2. It saves the nvim tabs with `mksession`. It does not use `options`, because `options` would restore the old runtimepath.
3. It quits nvim and starts the new nvim on the same socket from that session.
4. It respawns the yazi pane.

It leaves the claude pane (possibly the caller) and the shell pane running.

**`ide pop`.** It moves the current tmux window into a new WezTerm window. It works in any tmux window, not only in an `ide` window.

1. It creates a detached session named `pop-<window name>-<window id>`.
2. It moves the window into that session.
3. It starts `wezterm start -- tmux attach` on that session.

It refuses when the window is the only window of its session. Moving it would destroy the session and the client. When the window closes, the session ends, and the WezTerm window closes with it.

**Window options.** `ide` records the pane ids and the nvim socket as window options: `@ide_agent`, `@ide_dir`, `@ide_editor`, `@ide_files`, `@ide_shell`, `@ide_sock`.

**Layout hooks.** In `tmux.nix`, the hooks `client-attached` and `client-resized` run `ide-layout`. It re-proportions the panes to the window: yazi gets 15% of the width (clamped to 24-40 columns), claude gets 30%, and the shell gets 20% of the height.

**Environment.** The yazi, shell, and claude panes get `IDE_NVIM_SOCK` and `IDE_EDITOR_PANE`. They are set per pane, so several IDEs can share a session.

**Opening files from yazi.** The yazi `edit` opener is `ide-open`, in `yazi.nix`.

- It sends files to that nvim and focuses the nvim pane.
- Each file opens in its own tab through `genixis.ide.open` over `--remote-expr`. The call is scheduled, so it returns at once. A file that is already open switches to its tab. A blank fresh buffer is reused.
- If the old nvim was quit, it starts a new `nvim --listen` there. Outside an `ide` session, it opens nvim in a new tmux window.
- It must stay non-blocking. A blocking opener stalls yazi for seconds.

**Yazi settings:**

- Yazi shows a single column with no status bar. `mgr.ratio = [0 1 0]` means no parent pane and no preview. Dotfiles show through `mgr.show_hidden`.
- The `git` plugin (`yaziPlugins.git`, with its two `prepend_fetchers`) marks git status at the right of each row. Ignored files get a dark-grey sign, because yazi cannot hide gitignored files.
- `initLua` overrides `Root:layout` to give the status row a height of 0.
- `h` goes up. Enter uses the `smart-enter` plugin: it enters directories and does not send them to nvim.

**Viewer.** Shift+Enter in yazi runs `ide-view` on the hovered file.

- Yazi cannot see Shift+Enter under tmux, so tmux rewrites it to Alt+Enter in yazi panes.
- The viewer runs in a throwaway tmux session, swapped into the place of the editor pane. It uses glow for markdown and bat for other files. Ctrl+arrows still work.
- `q` swaps nvim back. `ide-open` also swaps it back before it opens a file.

**Tab keys:**

- Ctrl+0..9 switch nvim tabs. Ctrl+0 selects the 10th tab. The tabline is numbered to match.
  - In an `ide` window, tmux takes these keys from any pane and runs `ide-tab`. It calls `genixis.ide.tab` over the socket and focuses the editor.
  - Elsewhere, tmux passes the keys through to the maps of nvim itself.
- Ctrl+Tab and Ctrl+Shift+Tab go to the next and previous tab. They are `C-Tab` and `C-BTab` to tmux. WezTerm disables its own tab bindings for them. They run `ide-tab <window> next|prev`, which calls `genixis.ide.step`.
- tmux windows use the tmux default `prefix 0..9`.

**Terminal title.** tmux sets it (`set-titles`). An `ide` window shows its name (`<dir>` or `<dir>: <branch>`). Other windows show `<session>: <window>`.

**Closing files:**

- `<leader>x` closes a file. If the window is the only window of one of several tabs, it also closes the tab.
- `hidden` is off and `confirm` is on. So `:q` or `<leader>x` on a modified file asks to save right then. Without this, the changes would stay in a hidden buffer that appears only when you reopen the file.

**Popups.** `tmux.nix` binds `prefix g` to a lazygit popup. It binds `prefix D` to a lazydocker popup, but only where `programs.lazydocker.enable` is true.

### Aliases, tmux, and editor

- Aliases are for drop-in replacements that keep the familiar name: `cat→bat`. The `ls`, `ll`, `la`, `lt`, and `lla` aliases come from the integration of `programs.eza`.
- bat and eza use auto colour and icons, so piped output stays plain. Never set them to `always`.
- `tmux` is a function. Bare `tmux` runs `tmux new -As main`. When `SSH_CONNECTION` is set, it runs `ssh` instead, so an ssh login does not join the session of the local terminal. Any other call passes through.
- `EDITOR` is `nvim` everywhere (`programs.neovim.defaultEditor`). VSCodium stays installed as a fallback GUI editor.
- On NixOS, fish attaches on login by running bare `tmux`. Darwin skips this.
- Shift+Left and Shift+Right move by word at the fish prompt.
- Inside tmux, fish binds Ctrl-D to `delete-char`, so Ctrl-D never exits the shell. Use `exit`. The reason: WezTerm types Enter + Ctrl-D into a pane that it closes (Cmd+Q), and the tmux client forwards them to the focused pane.

## `modules/programs/darwin/` and `modules/programs/nixos/`

- `darwin/default.nix` enables `targets.darwin.copyApps` and disables `linkApps`. So the Home Manager `.app` bundles are real copies in `~/Applications/Home Manager Apps`, and Spotlight indexes them. The Dock (`common/darwin.nix`) pins those copies, not the `${pkgs.<app>}` store paths. Otherwise, apps that Spotlight starts would show up as a second Dock entry.
- `nixos/packages.nix` holds the bare enables for NixOS only (lazydocker).

## `modules/virtualisation/oci-containers/`

Podman containers are grouped by function, with one subdirectory for each group. To wire a group into `nixosConfigurations`, list its directory (or a flat file) in the module list of the host in `flake.nix`.

The directory names match their services 1:1. Run `ls` on a group to see its services. These groups load on these hosts:

- `media`: `media-downloaders/`, `media-managers/`, `media-servers/`.
- `services`: `caddy/`, `continuwuity/`, `forgejo/`, `invidious/`, `mealie/`, `monica/`, `radicale/`, `vaultwarden/`, and the flat file `languagetool.nix`.

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

Persistent data is always a bind mount under `/mnt/<service>/`. When a service has several mounts, use one subdirectory for each mount (for example `/mnt/romm/mysql` and `/mnt/romm/redis-data`). **Do not use named Podman volumes.** Create every bind-mount directory in the activation script.

### Multi-container pattern (isolated network)

Use this pattern when a service has a sidecar DB or companion:

```nix
system.activationScripts.create_foo-network.text = ''
  ${pkgs.podman}/bin/podman network create foo-network --ignore
'';
# Then in each container: networks = [ "foo-network" ]; dependsOn = [ "foo-db" ];
```

Examples: invidious (3 containers), romm (+ mariadb), monica (+ db), gamevault (+ postgres).

### VPN routing pattern (media-downloaders)

Gluetun is the VPN gateway. Deluge joins `gluetun-network` and depends on it. Its traffic is verified to exit through the VPN.

```nix
virtualisation.oci-containers.containers.my-downloader = {
  dependsOn = [ "gluetun" ];
  networks = [ "gluetun-network" ];
  # ...
};
```

Torrent clients must route through gluetun. `sabnzbd` (Usenet, TLS) and `shelfmark` currently do **not** join `gluetun-network`.

The secret of gluetun is at `./gluetun/environment.age`. It is in a subdirectory, not flat. The state of gluetun is at `/mnt/gluetun`. Deluge also mounts this directory read-only at `/pia` for the forwarded port.

### Secret patterns

- `environmentFiles` injects environment variables. This is the most common pattern.
- A volume-mounted secret file injects a config file: `"${config.age.secrets.foo.path}:/etc/service/config"`.
- Custom ownership: set `group`, `mode`, and `owner` on the secret attribute to match a container user that is not root. Recyclarr and Radicale do this.

### Notable per-service quirks

- **Jellyfin** uses `extraOptions = ["--network=host"]` (not `networks`). It needs this for mDNS/DLNA discovery. It is the only container that should do this. It still needs firewall rules.
- **pool.nix** (media-servers) is the one non-container file in that directory. It sets `boot.kernelPackages` for ZFS compatibility. It imports the `media` ZFS pool with autoScrub.
- **romm** commits `./romm/config.yaml` directly. The container bind-mounts it. It is not a secret and has no sensitive values. The `mariadb:latest` tag of romm follows the example compose file of upstream, on purpose.
- **recyclarr** mounts its config from an agenix secret (`./recyclarr/config.age`, which holds API keys). It runs as `user = "1000:1000"` to match the ownership of the secret.
- **invidious** copies SQL and init scripts from the pinned `invidious` flake input (`flake = false`). NixOS specialArgs pass the input. Update it with `nix flake update invidious`.
- **forgejo.nix** also runs the native `services.forgejo-runner` instance that executes the CI of this repository.
  - Its only label is `native:host`. Jobs run directly on `services` as the DynamicUser of the runner. They build through the sandboxed nix-daemon of the host.
  - A `docker://` label would add the runner to the rootful `podman` group. Builds in a job container run unsandboxed.
  - Put the tools that a job needs in its `hostPackages`.

### Activation script naming

Use `create_<service>_directory` or `create_<service>_directories` for directories. Use `create_<service>-network` for networks. The attribute name has underscores. The network name has hyphens. Always assign to `.text`.

### Debugging

```bash
journalctl -u podman-<service>   # container logs
podman ps -a                     # container states
podman network ls                # verify isolated networks were created
```

## `modules/services/`

### `tailscale/`

- Servers list the directory. `desktop` lists only `client.nix`.
- `client.nix` is what every tailnet member needs: `services.tailscale` and its firewall port.
  - On its own, it logs in once with `sudo tailscale up` and accepts no routes. `tailscale set --accept-routes=false` enforces this. The servers advertise the LAN that the client is already on. If the client accepted the routes, it would send replies to LAN peers out over the tailnet.
  - It lets `desktop` resolve the MagicDNS names of the servers (see the ssh note under NOTES).
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

## CI (`.forgejo/workflows/update-flake.yaml`)

The workflow runs daily and on dispatch, on the self-hosted Forgejo runner (`runs-on: native`, see forgejo.nix above). The steps are:

1. `nix fmt -- --ci`.
2. `nix flake update`.
3. `nix flake check --impure`.
4. Evaluate `darwinConfigurations.m2pro-mbp` and every `homeConfigurations` user. Flake check skips both.
5. Build the `media` and `services` toplevels. `desktop` is skipped, because it would compile the CachyOS kernel.
6. Commit `flake.lock` if it changed.

When you add a host, a user, or a Darwin config, add it to these steps.

## COMMITS

Use [Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>)!: <summary>`.

- **Summary:** lowercase, imperative, no trailing period. The whole subject line has at most 72 characters.
- **Types:**
  - `feat` — a new capability: a service, program, host, user, or option.
  - `fix` — a correction of wrong or unsafe behaviour.
  - `refactor` — a restructuring with no behaviour change (ideally identical derivations).
  - `style` — `nix fmt` or layout-only changes.
  - `chore` — dependency and lock bumps, removals, housekeeping.
  - `ci` — `.forgejo/workflows/`.
  - `docs` — AGENTS.md, README, comments only.
  - `revert`.
- **Scope** (optional): the one thing that the commit touches. Omit it when a commit spans several things.
  - A host: `media`, `desktop`, `darwin`.
  - A service or container: `romm`, `caddy`, `tailscale`.
  - A program: `fish`, `nvim`.
  - An area: `flake`, `home`, `common`, `containers`, `agenix`.
- **Breaking (`!` + `BREAKING CHANGE:` footer):** use it for anything that needs a manual step on the next rebuild. Examples: data migration, re-login, file cleanup. The footer says what to do.
- **Body:** explain *why*, and anything that the diff does not show. Use one topic for each commit. Each commit must evaluate on its own.
- The CI bot commit `chore: update flake inputs` already fits this standard. Leave it as it is.

## CODE STYLE

**Formatting:** Always run `nix fmt` (nixfmt-tree) before commit. Never format by hand. CI fails on unformatted files.

**Layout rules.** nixfmt preserves these rules but does not enforce them. Follow them by hand.

- **Multi-line:** Nested sets and non-empty lists always span multiple lines. Empty ones are `{ }` and `[ ]`. Exception: a one-item list passed as a function argument stays inline (`lib.hm.dag.entryAfter [ "writeBoundary" ]`).
- **Ordering:**
  - Sort keys A–Z, case-insensitive. Break ties by character code (`-` before `_`, shorter prefix first).
  - Single-line options and nested blocks sort together. Never group by shape.
  - Sort function arguments and `inherit` lists the same way. `...` goes last.
  - If a prefix gets a second key, merge both into one block. For example, `nix.settings.x` and `nix = { ... }` become one `nix` block.
- **`enable` and `inherit` come first.** A blank line follows them when other keys follow.
- **Domain-order exceptions:**
  - Containers start with `image`, then a blank line, then `hostname`/`pull`/`user`, then a blank line, then A–Z.
  - Flake inputs put `url` first.
  - disko puts `type` first.
  - starship puts `format` and `right_format` first.
  - VSCodium language blocks (`"[python]"`) go last.
  - Flake `outputs` arguments put `self` first.
  - `let` bindings follow dependency order.
- **Lists** sort A–Z too, except where the order has meaning:
  - Numbers, and port strings, sort numerically by host port.
  - Container `volumes` sort by container path. This keeps a parent mount before the files mounted inside it.
  - Positional arguments (`ExecStart`) and the Dock `persistent-apps` keep their order.
- **Blank lines:** Use one between top-level option paths. Use one between sibling entities (containers, systemd units, flake inputs). Otherwise use blank lines only to separate logical groups.
- **Quotes:** Do not quote keys that are valid identifiers. Write `users.users.root`, not `users.users."root"`.

Files and directories use kebab-case (`rclone-webdav.nix`, `media-servers`). Variables and functions use camelCase (`expandModules`, `homeModules`).

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

The `rebuild` and `rehome` fish functions (above) do the same against `git+https://forgejo.local.jracon.xyz/jracon/genixis` instead of `.`. They are for machines without a local checkout.

Forgejo is LAN-only. Sometimes it does not answer within 3 seconds (for example in WSL while the Windows host is on the work VPN). Then the functions fall back to the GitHub mirror, `git+https://github.com/jracon/genixis`. They also override the `themes` input with its mirror `git+https://github.com/jracon/themes` at the locked revision.

Use `git+https://`. Never use `github:` refs. They resolve through the rate-limited, unauthenticated GitHub API.

You must `git add` new files before the flake can see them.

## ANTI-PATTERNS

- Never commit the plaintext of `.age` secret files. Use `agenix` encryption.
- Never hardcode secrets in `.nix` files. Use `age.secrets.*` (see Secret patterns above).
- Never format by hand. Always use `nix fmt`.
- Never use `pull = "always"` on a container. Use `pull = "newer"`.
- Never omit firewall rules for an exposed container port. Never expose the port of a sidecar DB to the host.
- Never put multi-service orchestration in a flat `.nix` file. Give it a subdirectory.
- Never set `nixpkgs.config` or `nixpkgs.overlays` anywhere but `common/nixpkgs.nix`.
- Never fetch sources with unpinned `builtins.fetchGit` or `fetchTarball`. Add a flake input (`flake = false` for non-flakes).
- Do not reintroduce zsh config. The shell is fish now.
- Data directories are always at `/mnt/<service>/`. Shared media is always at `/mnt/media/`. Do not use named Podman volumes.

## NOTES

- Per-machine secrets and settings are in `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS). These files are **not committed**. Shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; syncthing-device-ids = { <hostname> = "..."; }; windows-efi-handle = "..."; }`.
- `modules/programs/cli/ssh.nix` adds plain `Host` blocks for `desktop`, `media`, and `services`. Each block has only the login user. The short names resolve through MagicDNS on the tailnet. With Tailscale off, they resolve through the DNS of the router on the LAN. The router registers DHCP hostnames, with the search domain `localdomain`. So the repository commits no address.
- ssh reaches Forgejo over Tailscale.
  - The Forgejo block in `.ssh/config.age` sets `HostName` to the MagicDNS name of `services`. The block is encrypted, so the tailnet name stays out of the public mirror. It sets `HostKeyAlias` to the known_hosts entry of the LAN name.
  - So every machine that pushes over ssh must run Tailscale. The servers and `desktop` do (`tailscale/client.nix`). The Mac and Windows (for WSL) run the app.
  - The reason is macOS. Local Network privacy credits a tmux server to the WezTerm that launched it. After that WezTerm quits, macOS blocks the LAN connections of the tmux server. The errors are "No route to host", or "Undefined error: 0" from the ssh of Apple. Tailnet addresses are not covered by this rule.
  - Other LAN traffic from tmux on the Mac is still affected. One example is the HTTPS fetch from Forgejo by `rebuild`, which then falls back to GitHub.
- The editor is VSCodium, not VSCode, because of unfree and license issues. `jeanp413.open-remote-ssh` (from the `nix-vscode-extensions` Open VSX set) replaces `ms-vscode-remote.remote-ssh`, which Microsoft locks.
