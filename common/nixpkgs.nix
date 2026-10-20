{
  nix-vscode-extensions,
  ...
}:

# shared by NixOS, nix-darwin and standalone Home Manager, which all expose the same nixpkgs.* options
{
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      nix-vscode-extensions.overlays.default
    ];
  };
}
