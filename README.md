# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
#### First-time Installation
First, boot from a NixOS installer. 

NOTE: All further commands will require sudo so running `sudo -s` is recommended. 

To start, run `nixos-generate-config --no-filesystems --root /tmp` to generate the initial `/tmp/etc/nixos/(hardware-)configuration.nix` (with `--no-filesystems` as disko will manage them). 

Create `/tmp/etc/nixos/local.nix` with any required disk information e.g.
```
{
  disks = [ "/dev/sda" ];
  disk-layout = "single-ext4";
}
```

Next, run `nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- -m destroy,format,mount -f github:jracon/genixis#disko` (optionally + `--yes-wipe-all-disks` to skip confirmation prompts) to format and mount the disk layout provided in `local.nix`.

Run `cp -r /tmp/etc /mnt` to copy all created configuration files to `/mnt` to persist after installation. 

Finally, run `nixos-install --impure --flake github:jracon/genixis#disko`, set a root password, and reboot!

#### Rebuild & Switch
First, run `nixos-generate-config` (with `--no-filesystems` if using disko) to ensure `/etc/nixos/(hardware-)configuration.nix` exists.

Next, run `nix-channel --update` to update the nixpkgs channel.

Finally, run `nixos-rebuild switch --impure --flake github:jracon/genixis#{ROLE}` to switch to the `ROLE` configuration.

#### Roles
##### Incus
To launch a new NixOS container, use the following command: `incus launch images:nixos/{NIXOS_RELEASE} {CONTAINER_NAME}`

### macOS
#### Rebuild & Switch
Run `darwin-rebuild switch --flake github:jracon/genixis#{HOSTNAME}` to switch to the `HOSTNAME` configuration. 

### Home Manager
#### Switch
Run `home-manager switch --impure --flake github:jracon/genixis#{USERNAME}` to enable to `USERNAME` user. 
