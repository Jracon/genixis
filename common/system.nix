{
  nixpkgs.hostPlatform = "x86_64-linux";
  nix.settings.auto-optimise-store = true;
  system-manager.allowAnyDistro = true;

  environment.etc = {
    "nix/nix.conf".replaceExisting = true;
  };
}
