# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
#### First-time Installation
First, boot from a NixOS installer. 

NOTE: All further commands will require sudo so running `sudo -s` is recommended. 

To start, run `nixos-generate-config --no-filesystems --root /tmp` to generate the initial `/tmp/etc/nixos/(hardware-)configuration.nix` (with `--no-filesystems` as disko will manage them). 

Create `/tmp/etc/nixos/local.nix` with any required disk information e.g.
```nix
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

Next, run `nixos-rebuild switch --impure --flake github:jracon/genixis#${ROLE}` to switch to the `ROLE` configuration.

### macOS
#### First Time Installation
First, install upstream Nix using the instructions found [here](https://github.com/DeterminateSystems/nix-installer).

Next, enable `Full Disk Access` for `Terminal` in `System Settings > Privacy & Security`. 

Then, install Rosetta and Xcode using `softwareupdate --install-rosetta --agree-to-license && xcode-select --install`.

Finally, run `sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake github:jracon/genixis#${HOSTNAME}` to switch to the `HOSTNAME` configuration.

#### Rebuild & Switch
Run `sudo darwin-rebuild switch --flake github:jracon/genixis#${HOSTNAME}` to switch to the `HOSTNAME` configuration. 

### Home Manager
#### Switch
First, run `useradd -m ${USERNAME}` to create the user and its associated home directory. 

Next, run `home-manager switch -b backup --impure --flake github:jracon/genixis#${USERNAME}` to build the `USERNAME` configuration. 
