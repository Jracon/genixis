{
  ...
}:

{
  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    settings.auto-optimise-store = true;
  };
}
