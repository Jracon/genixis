{
  nix.settings.auto-optimise-store = true;
  system-manager.allowAnyDistro = true;

  environment.etc = {
    "nix/nix.conf".replaceExisting = true;
  };
}
