# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
#### First-timex Installation
Boot from installer

generate temp configuration `sudo nixos-generate-config --no-filesystems --root /mnt`

run `sudo nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount --flake github:jracon/genixis?dir=nix-config#disko@{LAYOUT}`

run `sudo nixos-install --flake github:jracon/genixis?dir=nix-config#{LAYOUT}`, set a root password, and reboot


#### Rebuild & Switch
First, run `nixos-generate-config` to generate the initial `/etc/nixos/(hardware-)configuration.nix`.

Next, run `nix-channel --update` to update the nixpkgs "channel" (see https://nixos.wiki/wiki/Nix_channels).

Finally, run `nixos-rebuild switch --impure --flake "github:Jracon/genixis?dir=nix-config"#{HOSTNAME}`

### macOS
Run `darwin-rebuild switch --flake "github:Jracon/genixis?dir=nix-config"#{HOSTNAME}`
