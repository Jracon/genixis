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

#### Roles
##### Incus
###### Clustering
To enable a cluster, ensure that the bootstrap server has a `/etc/nixos/local.nix` that contains: 
```nix
{
  incus.bootstrap = true;
}
```

To add a new cluster member, run `incus cluster add ${NEW_MEMBER_NAME}` to generate a new token. Then, on the new member, run `incus admin init`, and answer the following accordingly:
```
Would you like to use Incus clustering? (yes/no) [default=no]: yes
Are you joining an existing cluster? (yes/no) [default=no]: yes
Do you have a join token? (yes/no/[token]) [default=no]: yes
Please provide join token: ${NEW_MEMBER_TOKEN}
```

###### Containers
To launch a new NixOS container, use the following command: `incus launch images:nixos/${NIXOS_RELEASE} ${CONTAINER_NAME}`

### macOS
#### Rebuild & Switch
Install Nix using the instructions from [here](https://github.com/DeterminateSystems/nix-installer).

Then, run `darwin-rebuild switch --flake github:jracon/genixis#${HOSTNAME}` to switch to the `HOSTNAME` configuration. 

### Home Manager
#### Switch
First, run `useradd -m ${USERNAME}` to create the user and its associated home directory. 

Next, run `home-manager switch --impure --flake github:jracon/genixis#${USERNAME}` to build the `USERNAME` configuration. 
