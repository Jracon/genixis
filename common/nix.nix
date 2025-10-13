{
  pkgs,
  ...
}:

{
  environment.systemPackages = [
    pkgs.nixfmt-rfc-style
  ];

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
  };

  nixpkgs.config.allowUnfree = true;
}
