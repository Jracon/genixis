# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
#### Fresh Install
First, run `nixos-generate-config --root /tmp/config --no-filesystems` to generate a temporary `/tmp/config/(hardware-)configuration.nix`.

Next, run `nix-channel --update` to update the nixpkgs "channel" (see https://nixos.wiki/wiki/Nix_channels).

Finally, run `sudo nix run --extra-experimental-features "nix-command flakes" "github:nix-community/disko/latest#disko-install" -- --write-efi-boot-entries --flake "github:Jracon/genixis?dir=nix-config/disko-config"#{LAYOUT} --disk main /foo/bar`

#### Standard Rebuild
First, run `nixos-generate-config` to generate the initial `/etc/nixos/(hardware-)configuration.nix`.

Next, run `nix-channel --update` to update the nixpkgs "channel" (see https://nixos.wiki/wiki/Nix_channels).

Finally, run `nixos-rebuild switch --impure --flake "github:Jracon/genixis?dir=nix-config"#{HOSTNAME}`

### macOS
Run `darwin-rebuild switch --flake "github:Jracon/genixis?dir=nix-config"#{HOSTNAME}`
