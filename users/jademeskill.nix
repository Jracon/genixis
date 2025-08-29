{
  ...
}:

{
  programs.home-manager.enable = true;

  nixpkgs.config.allowUnfree = true;
  targets.darwin.enable = true;
}
