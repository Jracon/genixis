# flake

How the flake loads its modules, which outputs it builds, and the Nix layout rules of the tree.

## Outputs and Hosts

This flake builds these outputs:

1. `nixosConfigurations`: `desktop`, `media`, and `services`. Entry `disko` is an install-time system, not a host.
2. `darwinConfigurations`: `m2pro-mbp`.
3. `homeConfigurations`: `jademeskill` and `root`. Each one is a standalone home, and it serves a machine that no system of this flake builds.
4. `checks`, `devShells`, `formatter`, and `packages`, for `aarch64-darwin` and `x86_64-linux`. The checks output holds the project check and the lint and scan checks of the gate and of the scheduled reports (lib/checks.nix, docs/ci.md). The packages output holds the network-bound check tools that the reports job runs.

Each NixOS host takes its name from its output name, and `mkDefault` keeps `networking.hostName` overridable.

## Module Loading

1. `expandModules` in flake.nix replaces a directory in a module list with every `.nix` file beneath it. A file or a non-path module passes through. A mistyped path fails the evaluation. Keep a non-module file out of the `.nix` extension, because the loader loads it as a module.
2. Home Manager program sets are chosen by platform in the `homeModules` function of flake.nix. Directory `modules/programs/cli` loads on every platform. On Darwin, `modules/programs/darwin` and `modules/programs/gui` load too. On NixOS, `modules/programs/nixos` loads, with `modules/programs/gui` only when `local.gui` is true.
3. Each home also loads `home.nix`, the agenix Home Manager module, and the palette name. Its default palette is `violet`. Host `desktop` sets `moss`.

Files under common/, by role:

- `agenix.nix`: the system key channel and the agenix CLI. Loaded by every host that declares system secrets.
- `base.nix`: the minimal base system, with flakes enabled and automatic garbage collection.
- `darwin.nix`: the macOS host defaults, for example the Dock, Finder, and Touch ID for sudo.
- `dummy-configuration.nix`: the evaluation fallback, a boot and root filesystem with no machine state, and it loads only when the machine holds no configuration.nix. Workaround record, the dummy fallback. Context: a local flake check needs a bootable system, and a bare checkout holds no configuration.nix. Decision: the dummy supplies one. Options that lost: no fallback, because a local flake check fails on a bare checkout. Consequences: the dummy reaches no real machine. Status: deferred. Cause: no verdict says whether the fallback is a standing pattern. Trigger and end: the owner takes the verdict, and the ruling lands in this record.
- `home-manager.nix`: Home Manager as a module of the system build, with the users from `homeUsers`.
- `homebrew.nix`: Homebrew through nix-homebrew, after the Nix profiles on the path.
- `llm-agents.nix`: the agent tools of the llm-agents input, with `claude-code`.
- `nixos.nix`: the NixOS defaults, for example fish as the login shell and five boot generations.
- `nixpkgs.nix`: the shared nixpkgs configuration, with the `nix-vscode-extensions` overlay.
- `ssh.nix`: openssh with password authentication off, and per-machine authorized keys from the `.ssh/authorized` directory for root and each home user. It loads on the desktop role and the server role.
- `plasma.nix`, `gaming.nix`, `wezterm-cli.nix`: one role each, loaded by the hosts that need it.

Each host loads its role and host modules from the lists in the `nixosConfigurations` attrset of flake.nix. That attrset is the authoritative list of what each host loads:

- `desktop`: the Plasma desktop, with the CachyOS kernel, the dual-boot setup, and the tailscale client.
- `media`: the server role with syncthing, the tailscale directory, and the three media container groups.
- `services`: the dev server role, with the dispatcher, the resilience modules, and the service containers.

Two platform directories complete the program set. `modules/programs/darwin/default.nix` copies the Home Manager app bundles into `~/Applications`, so Spotlight indexes them, instead of linking them. That file also holds the activate-agenix launchd guard, which docs/secrets.md records. `modules/programs/nixos/packages.nix` holds the bare enables that only NixOS loads, today lazydocker.

Machine-private state lives outside the repository. Outside the tree, the flake reads three files: `/etc/nixos/local.nix` on NixOS and for a standalone home, `/etc/nix-darwin/local.nix` for a standalone home on Darwin, and `/tmp/etc/nixos/local.nix` at install time. At install time, the flake also reads `/tmp/etc/nixos/configuration.nix`. Code reads four keys of the attrset:

1. `gui`: loads the GUI programs on NixOS when true.
2. `disk-layout`: names the partitioning template. Valid values are the file names under `disk-layouts/`. This repository holds one template today, `single-ext4`.
3. `disks`: the disk list of the template.
4. `windows-efi-handle`: the Windows EFI partition of the dual-boot host, read by modules/hardware/windows-dual-boot.nix.

Two fallbacks keep the evaluation running with no machine state:

1. With no `/etc/nixos/configuration.nix`, or at install time no `/tmp/etc/nixos/configuration.nix`, the build loads `common/dummy-configuration.nix`.
2. A missing `local.nix` becomes an empty attrset.

An optional file `users/<name>.nix` adds Home Manager settings for one user, and it loads when it exists. This repository commits no such file today.

Colours come from the themes flake. Input `themes` is the only input over `git+https` to the forge of the owner. Option `genixis.palette` in modules/programs/cli/palette.nix resolves the palette of that flake, and starship, tmux, lazygit, neovim, and wezterm consume the result.

## Declarative Law

Declarative Law, at its application in this topic (docs/design.md holds the map):

1. One place per decision. Each subject has one home in the tree. Shared nixpkgs configuration lives in common/nixpkgs.nix. An overlay that serves one subject lives with that subject's module, as the pinned kernel overlay lives with the cachyos kernel module. A Home Manager module never sets an option below nixpkgs.
2. Nothing downloads at runtime. Plugins, language servers, and formatters come from nixpkgs through the configs. No plugin manager is configured anywhere in the tree, and no tool fetches code from the network at its start.
3. Every source is pinned. Every input carries a lock entry, so a machine fetches a pinned revision and never resolves a ref. Ref resolution happens only when a person or CI updates the lock. Each URL that this repository writes for a machine uses `git+https`: the rebuild functions in `fish.nix` and the commands of the README. Input `themes`, the self-hosted input, uses `git+https`. The exception is install time: the one-shot tool commands of the README name the tools that run before this flake exists, for example the disko, nix-darwin, and home-manager runners.
4. Nix shadows the system package manager. Nix profiles come first on the path. On Darwin, Homebrew serves only what Nix does not.
5. Machine-private settings stay out of the tree. Per-machine facts and device identities live in an uncommitted local.nix, and secrets live in agenix files. This repository commits no machine facts and no key material.
6. One manager per home. Home Manager runs as a module of the system build. A standalone home exists only for a machine that no system of this flake builds, so two managers never fight over one home.
7. Platform purity. A module that Darwin loads holds no NixOS-only option, and the platform picker keeps the module sets apart. `nix flake check` skips `darwinConfigurations` and `homeConfigurations`, so the pull request gate and the update workflow each evaluate the darwin derivation and the three home derivations in their own step.
8. Each devShell of this flake holds the tools that edit its project. Global installs serve only files outside a project.

## Nix Layout Rules

`nix fmt` formats every .nix file with nixfmt-tree, and CI checks the result. The formatter owns indentation, line breaks, and the trailing commas. Run `nix fmt` before each commit, and never fix a formatting dispute by hand (AGENTS.md, TOOLS). The hand writes the structure that the formatter cannot decide: the order of the pieces, the comments, and the platform variance.

Rules that the hand keeps, each visible in the standing files:

1. One file holds one topic. A module file of one program names the program; a common/ file names the layer.
2. A module starts with the argument header on its own line, for example `{ config, lib, pkgs, ... }:`.
3. A `let` block holds the helpers of the file, and a one-sentence comment above each helper states its reason.
4. Flake inputs sit in name order (flake.nix).
5. A comment above an attribute states why the attribute holds its value, not what the value says.
6. Platform variance runs through the library, never through a copy of a block: `lib.mkIf`, `lib.mkDefault`, `lib.optional`, `lib.optionalString`.
7. A multi-line script sits in a `''` string.
8. A machine fact never enters the file: local.nix keys and agenix files carry it (docs/secrets.md).

One authority, the formatter, owns the layout, so no review argues about whitespace. A reader of any file finds the same shape, and a review argues about the state, not the layout. The Declarative Law above binds the structure: one place per decision, no machine facts in the tree, platform purity.

## What One Source Builds

Purpose of the flake: one source builds every machine the owner runs, and the same source answers a developer on any machine. Stance items 1 and 5 of docs/design.md state this criterion.

A new host is one entry in the output list plus its modules. A new program on every platform is one file under `modules/programs/cli`, because the loader expands the directory.

## Changing the Flake

Add a host:

1. Write the modules of the host under `modules/`.
2. Add the entry to `nixosConfigurations` with its module list.
3. Add the host to the steps of the update workflow, because that workflow names each host and each user of the flake (docs/ci.md).
4. Rebuild the host with the commands of the COMMANDS section of AGENTS.md.

Add a program:

1. Write one file under `modules/programs/cli`, or under the platform directory that the program needs.
2. Run `nix fmt`, then `nix flake check --impure`.

Change nixpkgs settings: put shared settings in common/nixpkgs.nix, and put an overlay that serves one subject in that subject's module.

Find the store path of a flake input: run `nix flake archive --json --dry-run`, and read `.inputs.<name>.path` of its output. Use it, not `nix eval`, because the global rules deny the eval forms (docs/forge-hook.md).

Set a machine fact: write the key into the local.nix of that machine, and keep the repository free of it.

Review a Nix change: read the `let` block and the comments first. A helper with no reason stated is a finding.
