# genixis

My declarative monorepo for tool configuration and reproducible Nix-enabled systems.

## How to Use

### Before You Start

The flake lives on Forgejo at `git+https://forgejo.local.jracon.xyz/jracon/genixis`, which is only reachable on the LAN. Off the LAN, use the GitHub mirror `git+https://github.com/jracon/genixis` instead, adding `--override-input themes git+https://github.com/jracon/themes` (the lock points the `themes` input at Forgejo too).

Flakes are fetched over `git+https`, which needs `git`. Where it's missing (e.g. NixOS-WSL or a fresh NixOS install), run the command inside `nix-shell -p git`.

Every machine needs the shared `genixis_secrets` SSH key (its public half is `.ssh/genixis_secrets.pub`) to decrypt its secrets:

- **NixOS and macOS:** the system reads it from `/root/.ssh/genixis_secrets` (NixOS) or `~/.ssh/genixis_secrets` (macOS).
- **Home Manager:** every user reads it from their own `~/.ssh/genixis_secrets`, including root and standalone users.

Copy the private key into place (mode `600`) before the first rebuild. Without it, the build still succeeds but secrets aren't decrypted, so the services and SSH config that use them won't work.

### Per-machine Settings (`local.nix`)

Settings that differ per machine, or shouldn't be committed, go in an uncommitted `/etc/nixos/local.nix`. On non-NixOS machines, standalone Home Manager reads `/etc/nix-darwin/local.nix` if there's no `/etc/nixos/local.nix`. Every key is optional:

```nix
{
  # disk(s) to install to, and the layout from disk-layouts/ to partition them with.
  # Keep these after installation: they also define the installed system's file systems
  disks = [
    "/dev/sda"
  ];
  disk-layout = "single-ext4";
  # adds GUI programs (from modules/programs/gui/) to Home Manager
  gui = true;
  # Syncthing device IDs of this machine's peers, by hostname (from `syncthing device-id` on each);
  # peers without one are skipped
  syncthing-device-ids = {
    some-hostname = "XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX";
  };
  # desktop only: EFI device handle of the Windows partition, for its boot menu entry
  # (find it with `map -c` in the EDK2 UEFI shell boot entry, e.g. "HD1b")
  windows-efi-handle = "HD1b";
}
```

### NixOS

#### First-time Installation

First, boot from a NixOS installer.

NOTE: All further commands need root, so running `sudo -s` is recommended.

To start, run `nixos-generate-config --no-filesystems --root /tmp` to generate the initial `/tmp/etc/nixos/(hardware-)configuration.nix` (with `--no-filesystems` as disko will manage them).

Create `/tmp/etc/nixos/local.nix` with at least `disks` and `disk-layout` (see [Per-machine Settings](#per-machine-settings-localnix)).

Next, run `nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- -m destroy,format,mount -f git+https://forgejo.local.jracon.xyz/jracon/genixis#disko` (optionally + `--yes-wipe-all-disks` to skip confirmation prompts) to format and mount the disk layout provided in `local.nix`.

Run `cp -r /tmp/etc /mnt` to copy all created configuration files to `/mnt` to persist after installation.

Finally, run `nixos-install --impure --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#disko`, set a root password, and reboot! Then follow Rebuild & Switch below.

#### Rebuild & Switch

First, run `nixos-generate-config` (with `--no-filesystems` if using disko) to ensure `/etc/nixos/(hardware-)configuration.nix` exists. Without `--force` it only refreshes `hardware-configuration.nix` and leaves an existing `configuration.nix` alone.

Next, make sure `/etc/nixos/local.nix` and the secrets key are in place (see [Before You Start](#before-you-start)).

Then, run `sudo nixos-rebuild switch --impure --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#${ROLE}` to switch to the `ROLE` configuration. This also applies Home Manager for `root`, plus `jademeskill` on `desktop`, `dev` on `services` and `nixos` on `wsl`.

Once that first rebuild has installed them, the fish functions `rebuild ${ROLE}` (from Forgejo, falling back to the GitHub mirror) and `local-rebuild ${ROLE}` (from a local checkout, run in its root) do the same, showing a package diff before switching.

### NixOS on WSL

#### First-time Installation

First, download `nixos.wsl` from the latest [NixOS-WSL release](https://github.com/nix-community/NixOS-WSL/releases/latest), then run `wsl --install --from-file nixos.wsl` in PowerShell and open it with `wsl -d NixOS`.

Next, edit `/etc/nixos/configuration.nix` and remove the `<nixos-wsl/modules>` import, since the flake provides NixOS-WSL itself. Keep `wsl.defaultUser` (`nixos`, matching its Home Manager user) and `system.stateVersion`. Don't run `nixos-generate-config` on WSL.

Then, put the secrets key in place for `root` and `nixos` (see [Before You Start](#before-you-start)).

Finally, run `sudo nixos-rebuild switch --impure --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#wsl`, then restart the distro with `wsl -t NixOS` from PowerShell.

#### Rebuild & Switch

Run `rebuild wsl` (or `local-rebuild wsl` from a local checkout). While Windows is on a VPN that can't reach the LAN, `rebuild` falls back to the GitHub mirror on its own.

### macOS

#### First-time Installation

First, install Nix with the [official installer](https://nixos.org/download/#nix-install-macos): `sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)`.

Next, enable `Full Disk Access` for `Terminal` in `System Settings > Privacy & Security`.

Then, install Rosetta and the Xcode Command Line Tools (which provide `git`) using `softwareupdate --install-rosetta --agree-to-license && xcode-select --install`, and put the secrets key in place (see [Before You Start](#before-you-start)).

Finally, run `sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin/master#darwin-rebuild -- switch --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#${HOSTNAME}` to switch to the `HOSTNAME` configuration. If nix-darwin refuses to overwrite files such as `/etc/nix/nix.conf`, `/etc/bashrc` or `/etc/zshrc`, rename each to `<file>.before-nix-darwin` as it asks and run it again.

#### Rebuild & Switch

Run `sudo darwin-rebuild switch --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#${HOSTNAME}` to switch to the `HOSTNAME` configuration. This also applies Home Manager for `jademeskill`.

Once the first switch has installed them, the fish functions `rebuild ${HOSTNAME}` and `local-rebuild ${HOSTNAME}` do the same.

### Home Manager (non-NixOS Linux)

NixOS and macOS hosts get Home Manager through their system configuration above; this standalone path is only for other machines.

First, install multi-user Nix following the instructions found [here](https://nixos.org/download/#nix-install-linux), run `useradd -m ${USERNAME}` if the user doesn't exist yet, and put the secrets key in its `~/.ssh` (see [Before You Start](#before-you-start)).

Next, run `nix --extra-experimental-features "nix-command flakes" run home-manager/master -- switch -b backup --impure --flake git+https://forgejo.local.jracon.xyz/jracon/genixis#${USERNAME}` to build the `USERNAME` configuration.

Once that first switch has installed them, the fish functions `rehome ${USERNAME}` and `local-rehome ${USERNAME}` do the same.
