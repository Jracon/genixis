# common/ - Shared Configuration Modules

Cross-platform configuration modules shared between NixOS, Darwin, and Home Manager.

---

## Structure

```
common/
├── agenix.nix              # Age-based secret encryption
├── darwin.nix              # macOS-specific settings
├── dummy-configuration.nix   # Fallback config for testing
├── enable-flakes.nix        # Enable Nix flakes
├── fonts.nix               # Font configuration
├── home-manager.nix         # Home Manager integration
├── homebrew.nix            # Homebrew for macOS
├── llm-agents.nix          # LLM agents configuration
├── minimal.nix             # Minimal base configuration
├── nix.nix                # Nix package manager settings
├── nixos.nix              # NixOS-specific settings
└── ssh.nix                 # SSH configuration
```

---

## Where to Look

| Task                  | File           | Notes                            |
| --------------------- | -------------- | -------------------------------- |
| Add shared setting    | `*.nix`        | Use appropriate domain file      |
| Modify macOS defaults | `darwin.nix`   | Dock, Finder, system preferences |
| Add secret            | `agenix.nix`   | Never commit secrets directly    |
| Add Homebrew cask     | `homebrew.nix` | macOS GUI applications           |

---

## Patterns

### macOS System Defaults

Darwin-specific system settings in `darwin.nix`:

```nix
{
  system.defaults.dock.autohide = true;
  system.defaults.finder.AppleShowAllFiles = true;
  system.defaults.NSGlobalDomain.AppleInterfaceStyle = "Dark";
}
```

### Cross-Platform Services

Services that work across platforms (in `*.nix`):

```nix
{
  services.tailscale.enable = true;
  programs.git.enable = true;
}
```

### Home Manager Activation

Home Manager home directory scripts in `home-manager.nix`:

```nix
{
  home-manager.users.jademeskill = {
    home.activation.setupScript = ''
      mkdir -p $HOME/.config/app
    '';
  };
}
```

---

## Anti-Patterns

- **Committing secrets**: Use `agenix` encryption, never plain text
- **Platform mixing**: Don't put Darwin-specific config in `nixos.nix`
- **Hardcoded paths**: Use relative paths or Nix builtins
