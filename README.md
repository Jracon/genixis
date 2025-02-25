# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
#### First-time Installation
First, boot from a NixOS installer. 

NOTE: All further commands will require sudo so running `sudo -s` is recommended. 

First, run `nixos-generate-config --no-filesystems --root /mnt` to generate the initial `/mnt/etc/nixos/(hardware-)configuration.nix` (with `--no-filesystems` as disko will manage them). 

Next, run `nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount --flake github:jracon/genixis?dir=nix-config#disko@{HOSTNAME}` (optionally +`--yes-wipe-all-disks`) to format and mount the provided `HOSTNAME` disk layout.

Finally, run `nixos-install --impure --flake github:jracon/genixis?dir=nix-config#disko@{HOSTNAME}`, set a root password, and reboot!

#### Rebuild & Switch
First, run `nixos-generate-config` to ensure `/etc/nixos/(hardware-)configuration.nix` exists (optionally +`--no-filesystems` if disko will manage them).

Next, run `nix-channel --update` to update the nixpkgs channel.

Finally, run `nixos-rebuild switch --impure --flake github:jracon/genixis?dir=nix-config#{HOSTNAME}` to switch to the `HOSTNAME` configuration after a reboot. 

#### Roles
##### Incus
To launch a new NixOS container, use the following command: `incus launch images:nixos/24.11 {CONTAINER_NAME} -c security.nesting=true`

### macOS
#### Rebuild & Switch
Run `darwin-rebuild switch --flake github:jracon/genixis?dir=nix-config#{HOSTNAME}` to switch to the `HOSTNAME` configuration after a reboot. 
