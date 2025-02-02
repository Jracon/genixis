# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
First, run `nixos-generate-config` to generate the initial `/etc/nixos/(hardware-)configuration.nix`.

Next, run `nix-channel --update` to update the nixpkgs "channel" (see https://nixos.wiki/wiki/Nix_channels).

Finally, run `nixos-rebuild switch --impure --flake "github:Jracon/genixis/test?dir=nix-config"#{HOSTNAME}`

### macOS
Run `darwin-rebuild switch --flake "github:Jracon/genixis/test?dir=nix-config"#{HOSTNAME}`
