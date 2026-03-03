# AGENTS.md - Nix Configuration Repository Guide

**Generated:** 2026-03-03 | **Commit:** 02e0b2c | **Branch:** main

Declarative Nix flake monorepo for NixOS, macOS (nix-darwin), and Home Manager — self-hosted media stack + productivity services via Podman OCI containers.

---

## STRUCTURE

```
genixis/
├── flake.nix              # Outputs: darwinConfigurations, homeConfigurations, nixosConfigurations
├── home.nix               # Home Manager base — platform-aware homeDirectory, stateVersion
├── secrets.nix            # agenix public key declarations (one SSH key for all secrets)
├── common/                # Modules auto-included by every host configuration
├── modules/
│   ├── programs/cli/      # One .nix per CLI tool; loaded for all platforms
│   ├── programs/gui/      # macOS-only GUI apps (vscode, wezterm)
│   ├── programs/darwin/   # darwin-specific program defaults
│   ├── services/tailscale/ # Tailscale service module
│   └── virtualisation/
│       ├── podman.nix     # Backend config + daily autoPrune
│       └── oci-containers/ # Self-hosted services grouped by function
├── users/                 # Per-user Home Manager overrides (minimal)
└── disk-layouts/          # Disko partitioning templates
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add shared config | `common/` | Applies to NixOS, Darwin, Home Manager |
| Add container | `modules/virtualisation/oci-containers/` | See subdirectory AGENTS.md |
| Add CLI tool | `modules/programs/cli/` | One file per tool |
| Add GUI app | `modules/programs/gui/` | macOS-only |
| Configure host | `flake.nix` outputs | NixOS: `nixosConfigurations`, Darwin: `darwinConfigurations` |
| User config | `users/${username}.nix` | Per-user Home Manager overrides |
| Disk layout | `disk-layouts/` | Used by disko module |
| Secrets | `secrets.nix` + `age.secrets.*` in module | Declare in secrets.nix; consume via `config.age.secrets.*.path` |

## MODULE LOADING (flake.nix)

`generateConfigModules` resolves module paths from host config keys:
- `programs = ["cli" "gui"]` → loads all `.nix` files under `modules/programs/cli/` and `modules/programs/gui/`
- `services = ["tailscale"]` → loads `modules/services/tailscale.nix`
- `virtualisation = ["podman" "oci-containers/media-servers"]` → loads all `.nix` in the matching directory
- Both exact files (`tailscale.nix`) and whole directories are supported — directory loads all `.nix` files in it

**Configuration targets:**
- NixOS: `bare` (empty), `media` (arr stack + downloaders), `services` (productivity/infra), `disko` (install-time)
- Darwin: `m2pro-mbp`
- Home Manager: `jademeskill`, `root`

## CODE STYLE

**Formatting:** `nix fmt` (nixfmt) — always before commit, never manually format.

| Context | Convention | Examples |
|---------|------------|---------|
| Files | kebab-case | `tailscale.nix`, `vaultwarden.nix` |
| Directories | kebab-case | `oci-containers`, `media-servers` |
| Variables/functions | camelCase | `generateConfigModules`, `containerNames` |

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

## COMMON PATTERNS

**OCI container:**
```nix
virtualisation.oci-containers.containers.my-service = {
  image = "repo/image:tag";
  hostname = "my-service";
  pull = "newer";  # always present
  ports = [ "8080:80" ];
  volumes = [ "/mnt/data:/data" ];
  environment.TZ = "America/Phoenix";
};
```

**agenix secret:**
```nix
age.secrets.my_secret.file = ./secret.age;
# Consume:
environmentFiles = [ config.age.secrets.my_secret.path ];
# Or mount into container:
volumes = [ "${config.age.secrets.my_secret.path}:/etc/service/secret" ];
```

**Activation script (directory creation):**
```nix
system.activationScripts.create_foo_directory.text = ''
  mkdir -p /mnt/foo
'';
```

**Systemd timer:**
```nix
systemd.timers."my-job" = {
  timerConfig.OnCalendar = "daily";
  wantedBy = [ "timers.target" ];
};
systemd.services."my-job" = {
  script = ''#!/bin/bash
# script'';
  serviceConfig.Type = "oneshot";
};
```

**Isolated network (multi-container):**
```nix
system.activationScripts.create_foo-network.text = ''
  ${pkgs.podman}/bin/podman network create foo-network --ignore
'';
# Then in containers: networks = [ "foo-network" ];
```

## COMMANDS

```bash
nix fmt                                                          # Format all .nix files
nix flake check                                                  # Validate (macOS: skips NixOS configs)
nixos-rebuild switch --impure --flake .#${ROLE}                  # Apply NixOS
sudo darwin-rebuild switch --flake .#${HOSTNAME}                  # Apply macOS
home-manager switch --impure --flake .#${USERNAME}               # Apply Home Manager
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel  # Dry build
nix repl .#nixosConfigurations.<host>.config                     # Debug interactively
nix flake update                                                 # Bump all inputs
```

## ANTI-PATTERNS

- Never commit `.age` secret files' plaintext — use `agenix` encryption
- Never hardcode secrets in `.nix` files — use `age.secrets.*`
- Never manually format — always `nix fmt`
- Never set `pull = "always"` — use `pull = "newer"` (standard in this repo)
- Never omit firewall port rules when adding a container
- Never add `nixpkgs.config.allowUnfree = true` globally — only in `users/*.nix`

## NOTES

- Per-machine secrets/settings: `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS) — **not committed**
- `local.nix` shape: `{ disks = ["/dev/sda"]; disk-layout = "single-ext4"; gui = true; }`
- Container data at `/mnt/<service>/`; media at `/mnt/media/`
- Debug containers: `journalctl -u podman-<service>`
- `common/llm-agents.nix` installs `claude-code`, `opencode`, `pi` system-wide via numtide/llm-agents.nix flake
- Darwin: VSCode is temporary (`TODO: switch to vscodium when remote-ssh works`)
