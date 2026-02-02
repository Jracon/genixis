# AGENTS.md - Nix Configuration Repository Guide

Declarative Nix flake repository for managing system configurations across NixOS, macOS (nix-darwin), and Home Manager.

## Commands

```bash
# Format all Nix files
nix fmt

# Check flake structure (Darwin-friendly: skips NixOS configs)
nix flake check

# Build specific configuration
nix build .#nixosConfigurations.${HOSTNAME}.config.system.build.toplevel
nix build .#darwinConfigurations.${HOSTNAME}.config.system.build.toplevel

# Apply NixOS configuration
nixos-rebuild switch --impure --flake .#${ROLE}

# Apply macOS configuration
sudo darwin-rebuild switch --flake .#${HOSTNAME}

# Apply Home Manager configuration
home-manager switch --impure --flake .#${USERNAME}

# Update flake inputs
nix flake update
```

## Directory Structure

```
genixis/
├── flake.nix              # Main flake entry point
├── common/                # Shared config modules (agenix, darwin, nix, etc.)
├── modules/               # Reusable modules
│   ├── programs/          # Program configs (cli, gui, darwin)
│   ├── services/          # System services (tailscale)
│   └── virtualisation/   # Container/VM configs (oci-containers, podman)
├── users/                 # User-specific configs (jademeskill, root)
├── disk-layouts/          # Disk partitioning templates
├── home.nix               # Home Manager base config
└── secrets.nix           # Secret management definitions
```

## Code Style

### Formatting
- Use `nix fmt` (configured with nixfmt)
- Never manually format or use inconsistent indentation

### Naming Conventions
| Context | Convention | Examples |
|----------|-------------|----------|
| Files | kebab-case | `tailscale.nix`, `vaultwarden.nix` |
| Directories | kebab-case | `oci-containers`, `media-servers` |
| Variables | camelCase | `generateConfigModules`, `containerNames` |

### File Structure

**Simple modules** (most common):
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

**With local variables**:
```nix
{
  local,
  ...
}:
let
  primaryDisk = builtins.elemAt local.disks 0;
in
{
  # Configuration using primaryDisk
}
```

**Minimal configs**:
```nix
{
  programs.git.enable = true;
}
```

## Common Patterns

### OCI Containers
```nix
virtualisation.oci-containers.containers = {
  vaultwarden = {
    image = "vaultwarden/server:latest";
    hostname = "vaultwarden";
    pull = "newer";
    environmentFiles = [ config.age.secrets.vaultwarden_environment.path ];
    ports = [ "5555:80" ];
    volumes = [ "/mnt/vaultwarden:/data" ];
  };
}
```

### Age Secrets
```nix
{
  age.secrets.vaultwarden_environment.file = ./environment.age;
  services.my-service = {
    environmentFiles = [ config.age.secrets.vaultwarden_environment.path ];
  };
}
```

### Systemd Timers
```nix
{
  systemd.timers."backup" = {
    timerConfig.OnCalendar = "daily";
    wantedBy = [ "timers.target" ];
  };
  systemd.services."backup" = {
    script = "#!/bin/bash\n# Backup script here";
    serviceConfig.Type = "oneshot";
  };
}
```

### Activation Scripts
```nix
{
  system.activationScripts.create_directories.text = ''
    mkdir -p /mnt/service-data /mnt/configs
  '';
}
```

## Development Workflow

1. Make changes to relevant `.nix` files
2. Run `nix fmt` to format
3. Run `nix flake check` to validate
4. Test with `nix build .#<target>` if applicable
5. Apply using appropriate rebuild command
6. Commit with descriptive messages

## Important Notes

- **Darwin builds**: `nix flake check` skips NixOS/disko configs on macOS
- **Secrets**: Never commit secrets - use `agenix` (see `secrets.nix`)
- **Unfree packages**: Set `nixpkgs.config.allowUnfree = true` judiciously
- **Debugging**: Use `nix repl .#nixosConfigurations.<host>.config` to inspect configs
- **Containers**: Check `journalctl -u podman` for container issues

## Configuration Targets

- **NixOS**: `bare`, `media`, `services`, `disko`
- **Darwin**: `m2pro-mbp`
- **Home Manager**: `jademeskill`, `root`
