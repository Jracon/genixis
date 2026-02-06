{
  pkgs,
  ...
}:

{
  # allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # enable nixfmt
  environment.systemPackages = with pkgs; [
    nixfmt
    nixfmt-tree
  ];

  # automatically optimise the Nix store and enable automatic garbage collection
  nix = {
    gc.automatic = true;
    optimise.automatic = true;
  };
}
