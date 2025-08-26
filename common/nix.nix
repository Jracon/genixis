{
  ...
}:

{
  services.nix-daemon.enable = true;

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    settings.optimise-store = true;
  };
}
