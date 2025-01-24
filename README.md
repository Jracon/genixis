# genixis
My declarative monorepo for tool configuration and reproducible Nix-enabled systems. 

## How to Use
### NixOS
First, run 
```bash
nixos-generate-config
```
to generate the initial `(hardware-)configuration.nix`.

Next, run 
```bash
nix run github:nix-community/nixos-anywhere --experimental-features 'nix-command flakes' -- --flake "github:Jracon/genixis/test?dir=nix-config"#CONFIGURATION_HERE
```

### macOS
