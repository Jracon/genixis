{
  # allow unfree packages
  nixpkgs.config.allowUnfree = true;

  system-manager.allowAnyDistro = true;
}
