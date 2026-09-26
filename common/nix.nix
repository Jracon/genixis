{
  ...
}:

{
  # allow unfree packages
  nixpkgs.config.allowUnfree = true;
  nix.settings.auto-optimise-store = true;

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
  };
}
