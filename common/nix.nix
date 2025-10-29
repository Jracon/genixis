{
  pkgs,
  ...
}:

{
  # enable nixfmt
  environment.systemPackages = [
    pkgs.nixfmt-rfc-style
  ];

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
  };

  # allow unfree packages
  nixpkgs.config.allowUnfree = true;

  programs.nix-ld.enable = true;
}
