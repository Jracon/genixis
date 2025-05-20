{
  ...
}:

{
  # remove all default packages for a minimal base system
  environment.defaultPackages = [ ];

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
  };
}
