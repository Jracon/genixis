{
  pkgs,
  ...
}:

{
  nixpkgs.hostPlatform = "x86_64-linux";
  system-manager.allowAnyDistro = true;

  nix = {
    enable = true;
    settings.auto-optimise-store = true;
  };
}
