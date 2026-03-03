# common/ — Shared Host Modules

Auto-included by every host configuration (NixOS, Darwin, Home Manager via `darwinConfiguration` and `nixosConfiguration` in flake.nix).

## FILES

| File | Purpose | Hosts |
|------|---------|-------|
| `agenix.nix` | Wires agenix module | All |
| `darwin.nix` | macOS system defaults (dock, finder, trackpad, Touch ID sudo) | Darwin only |
| `dummy-configuration.nix` | Placeholder when `/etc/nixos/configuration.nix` absent | Disko/bare install |
| `enable-flakes.nix` | Enables nix flakes + nix-command experimental features | All |
| `fonts.nix` | System-wide font packages | All |
| `home-manager.nix` | Wires home-manager module + per-user config | All |
| `homebrew.nix` | nix-homebrew taps + brews + casks | Darwin only |
| `llm-agents.nix` | Installs `claude-code`, `opencode`, `pi` from numtide/llm-agents.nix | All |
| `minimal.nix` | Strips `environment.defaultPackages` to empty | All |
| `nix.nix` | Nix daemon / gc / store settings | All |
| `nixos.nix` | NixOS-specific base (users, sudo, etc.) | NixOS only |
| `ssh.nix` | SSH daemon + authorized keys | NixOS only |

## CONVENTIONS

- `darwin.nix` uses `self.rev or self.dirtyRev` for `system.configurationRevision` — keep `self` in specialArgs
- `dummy-configuration.nix` exists solely so disko builds don't fail when no host config exists yet — never edit it
- `llm-agents.nix` takes `llm-agents` input (numtide flake) — must be in specialArgs

## ANTI-PATTERNS

- Never put NixOS-only options in files loaded on Darwin (check host inclusion list in flake.nix first)
- Never add per-user `allowUnfree` here — belongs in `users/*.nix`
- Never add service/container config here — use `modules/`
