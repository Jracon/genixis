# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Declarative Nix flake monorepo for managing system configurations across NixOS, macOS (nix-darwin), and Home Manager.

> See also: `AGENTS.md` (full reference), `common/AGENTS.md`, `modules/virtualisation/oci-containers/AGENTS.md`, `modules/programs/cli/AGENTS.md`, `modules/virtualisation/oci-containers/media-{servers,managers,downloaders}/AGENTS.md`

---

## Commands

```bash
# Format all Nix files
nix fmt

# Validate flake (skips NixOS configs when run on macOS)
nix flake check

# Build a specific configuration without applying
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel
nix build .#darwinConfigurations.${HOSTNAME}.config.system.build.toplevel

# Apply configuration
nixos-rebuild switch --impure --flake .#${ROLE}       # NixOS
sudo darwin-rebuild switch --flake .#${HOSTNAME}       # macOS
home-manager switch --impure --flake .#${USERNAME}     # Home Manager

# Inspect a config interactively
nix repl .#nixosConfigurations.<host>.config

# Update flake inputs
nix flake update
```

**Configuration targets:**

- NixOS: `bare`, `media`, `services`, `disko`
- Darwin: `m2pro-mbp`
- Home Manager: `jademeskill`, `root`

---

## Architecture

### Module System

`flake.nix` uses `generateConfigModules` to dynamically resolve modules. Each host specifies which programs/services/virtualisation features to enable; the function loads matching `.nix` files from `modules/`.

```
common/          # Shared modules applied across platforms (agenix, fonts, ssh, etc.)
modules/
  programs/cli/  # One file per CLI tool (zsh, neovim, tmux, git, etc.)
  programs/gui/  # macOS-only GUI apps (vscode, wezterm)
  services/      # System services (tailscale)
  virtualisation/oci-containers/  # Podman-based self-hosted services
users/           # Per-user Home Manager config
disk-layouts/    # Disko disk partitioning templates
home.nix         # Home Manager base (platform-aware paths)
secrets.nix      # agenix secret file declarations
```

### Self-Hosted Services (Podman OCI containers)

Services are grouped by function under `modules/virtualisation/oci-containers/`:

- **Media downloaders**: Deluge, SABnzbd, Shelfmark, Gluetun (VPN tunnel)
- **Media managers**: Radarr, Sonarr, Bazarr, Prowlarr, Jellyseerr, Kapowarr, Recyclarr, Calibre
- **Media servers**: Jellyfin, Kavita, GameVault, RomM, Syncthing, Pool
- **Productivity/infra**: Caddy, Vaultwarden, Forgejo, Mealie, Monica, LanguageTool, Invidious

### Secret Management

Secrets use `agenix` (age encryption). Never commit plaintext secrets. All `.age` files live alongside their service module and are declared in `secrets.nix`.

```nix
age.secrets.my_secret.file = ./secret.age;
# Consumed via: config.age.secrets.my_secret.path
```

---

## Code Style

- **Formatter**: `nix fmt` (nixfmt) — always run before committing
- **Files/directories**: kebab-case (`tailscale.nix`, `oci-containers`)
- **Variables/functions**: camelCase (`generateConfigModules`)

### Module structure

```nix
# Simple module
{ config, pkgs, ... }:
{
  services.tailscale.enable = true;
}

# With local variables
{ local, ... }:
let
  primaryDisk = builtins.elemAt local.disks 0;
in
{
  # use primaryDisk
}
```

### OCI container pattern

```nix
virtualisation.oci-containers.containers.my-service = {
  image = "image:tag";
  ports = [ "8080:80" ];
  volumes = [ "/mnt/data:/data" ];
  environment.TZ = "America/Phoenix";
  pull = "newer";
};
```

---

## Important Notes

- Per-machine secrets/settings live in `/etc/nixos/local.nix` (NixOS) or `/etc/nix-darwin/local.nix` (macOS) and are not committed
- Container issues: `journalctl -u podman`
- Always open firewall ports when adding a new container service
