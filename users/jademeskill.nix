{
  ...
}:

{
  programs.home-manager.enable = true;

  nixpkgs.config.allowUnfree = true;

  targets.darwin.linkApps.enable = true;
}
