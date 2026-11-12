# flake

How the flake loads its modules and which outputs it builds.

## What Is the Topic?

This flake builds these outputs (flake.nix:369-471):

1. `nixosConfigurations`: `bare`, `desktop`, `media`, `services`, and `wsl`. The entry `disko` is an install-time system, not a host.
2. `darwinConfigurations`: `m2pro-mbp` (flake.nix:381-383).
3. `homeConfigurations`: `jademeskill`, `nixos`, and `root`. Each one is standalone, for a machine that no system of this flake builds (flake.nix:241, 409-413).
4. `checks`, `devShells`, and `formatter`, for `aarch64-darwin` and `x86_64-linux` (flake.nix:369-408).

Each NixOS host takes its name from its output name, and `networking.hostName` stays overridable (flake.nix:415-425).

## How Is the Topic Realized?

Module loading:

1. `expandModules` replaces a directory in a module list with every `.nix` file beneath it (flake.nix:86-94). A file or a non-path module passes through. A mistyped path fails the evaluation.
2. Home Manager program sets are chosen by platform (flake.nix:107-143). Directory `modules/programs/cli` loads on every platform. On Darwin, `modules/programs/darwin` and `modules/programs/gui` load too. On NixOS, `modules/programs/nixos` loads, with `modules/programs/gui` only when `local.gui` is true.
3. Each home also loads `home.nix`, the agenix Home Manager module, and the palette name (flake.nix:112-126). Its default palette is `violet`. Host `desktop` sets `moss` (flake.nix:325).

Files under common/, by role:

- `agenix.nix`: the system key channel and the agenix CLI. Loaded by every host that declares system secrets.
- `base.nix`: the minimal base system, with flakes enabled and automatic garbage collection (common/base.nix:7-25).
- `darwin.nix`: the macOS host defaults, for example the Dock, Finder, and Touch ID for sudo.
- `dummy-configuration.nix`: the evaluation fallback, a boot and root filesystem with no machine state (common/dummy-configuration.nix:6-15).
- `home-manager.nix`: Home Manager as a module of the system build, with the users from `homeUsers` (common/home-manager.nix:9-17).
- `homebrew.nix`: Homebrew through nix-homebrew, after the Nix profiles on the path (common/homebrew.nix:11-15).
- `llm-agents.nix`: the agent tools of the llm-agents input, with `claude-code` (common/llm-agents.nix:9-19).
- `nixos.nix`: the NixOS defaults, for example fish as the login shell and five boot generations (common/nixos.nix:9-30).
- `nixpkgs.nix`: the one place for nixpkgs configuration, with the `nix-vscode-extensions` overlay (common/nixpkgs.nix:8-13).
- `plasma.nix`, `gaming.nix`, `wsl.nix`, `wezterm-cli.nix`: one role each, loaded by the hosts that need it (flake.nix:321-366).

Each host loads its role and host modules from these lists (flake.nix:428-467):

- `bare`: a server with no host module.
- `desktop`: the Plasma desktop, with the CachyOS kernel, the dual-boot setup, and the tailscale client.
- `media`: the server role with syncthing, the tailscale directory, and the three media container groups.
- `services`: the dev server role, with the dispatcher, the resilience modules, and the service containers.
- `wsl`: the WSL role for the `nixos` user.

Two platform directories complete the program set. `modules/programs/darwin/default.nix` copies the Home Manager app bundles into `~/Applications`, so Spotlight indexes them, instead of linking them (modules/programs/darwin/default.nix:2-6). `modules/programs/nixos/packages.nix` holds the bare enables that only NixOS loads, today lazydocker (modules/programs/nixos/packages.nix:3).

A directory in a module list expands into every `.nix` file beneath it, so keep a non-module file out of the `.nix` extension (flake.nix:86-94).

Machine-private state lives outside the repository. Outside the tree, the flake reads three files: `/etc/nixos/local.nix` on NixOS and for a standalone home, `/etc/nix-darwin/local.nix` for a standalone home on Darwin, and `/tmp/etc/nixos/local.nix` at install time (flake.nix:205, 232-235, 271). Code reads four keys of the attrset:

1. `gui`: loads the GUI programs on NixOS when true (flake.nix:257, 311).
2. `disk-layout`: names the partitioning template. Valid values are the file names under `disk-layouts/` (flake.nix:96-105). This repository holds one template today, `single-ext4` (disk-layouts/single-ext4.nix).
3. `disks`: the disk list of the template (disk-layouts/single-ext4.nix:7).
4. `windows-efi-handle`: the Windows EFI partition of the dual-boot host (modules/hardware/windows-dual-boot.nix:14).

Two fallbacks keep the evaluation running with no machine state:

1. With no `/etc/nixos/configuration.nix`, the build loads `common/dummy-configuration.nix` (flake.nix:287-295).
2. A missing `local.nix` becomes an empty attrset (flake.nix:205, 237, 271).

An optional file `users/<name>.nix` adds Home Manager settings for one user, and it loads when it exists (flake.nix:260, common/home-manager.nix:15). This repository commits no such file today.

Colours come from the themes flake. Input `themes` is the only input over `git+https` to the forge of the owner (flake.nix:58-61). Option `genixis.palette` resolves the palette of that flake (modules/programs/cli/palette.nix:9-20), and starship, tmux, lazygit, neovim, and wezterm consume the result.

## Why Is the Topic That Way?

Declarative Law, at its application in this topic (docs/design.md holds the map):

1. One place per decision. Each subject has one home in the tree. All nixpkgs configuration and all overlays live in common/nixpkgs.nix, and a Home Manager module never sets an option below nixpkgs.
2. Nothing downloads at runtime. Plugins, language servers, and formatters come from nixpkgs. No tool runs its own package manager, and no tool fetches code from the network at its start. Runtime enforcement of the pinning is the purpose: plugin managers, Mason-style installs, and startup fetchers stay blocked.
3. Every source is pinned. A dependency is a flake input with a lock entry, and an unpinned fetch has no place here. Each automatic fetch uses git+https, never a rate-limited public API. A command that a person types may use another form.
4. Nix shadows the system package manager. Nix profiles come first on the path. On Darwin, Homebrew serves only what Nix does not.
5. Machine-private settings stay out of the tree. Per-machine facts and device identities live in an uncommitted local.nix, and secrets live in agenix files. This repository commits no machine facts and no key material.
6. One manager per home. Home Manager runs as a module of the system build. A standalone home exists only for a machine that no system of this flake builds, so two managers never fight over one home.
7. Platform purity. A module that Darwin loads holds no NixOS-only option, and the platform picker keeps the module sets apart.
8. Each devShell of this flake holds the tools that edit its project. Global installs serve only files outside a project.

## What Does the Topic Enable?

Purpose of the flake: one source builds every machine the owner runs, and the same source answers a developer on any machine. Stance items 1 and 5 of docs/design.md state this criterion.

A new host is one entry in the output list plus its modules. A new program on every platform is one file under `modules/programs/cli`, because the loader expands the directory.

## How Does a Reader Use and Change the Topic?

Add a host:

1. Write the modules of the host under `modules/`.
2. Add the entry to `nixosConfigurations` with its module list (flake.nix:428-467).
3. Rebuild the host with the commands of the COMMANDS section of AGENTS.md.

Add a program:

1. Write one file under `modules/programs/cli`, or under the platform directory that the program needs.
2. Run `nix fmt`, then `nix flake check --impure`.

Change nixpkgs settings: edit common/nixpkgs.nix, the one place for them.

Set a machine fact: write the key into the local.nix of that machine, and keep the repository free of it.
