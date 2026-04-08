{
  pkgs,
  ...
}:

{
  nix.settings.auto-optimise-store = true;
  nixpkgs.hostPlatform = "x86_64-linux";
  system-manager.allowAnyDistro = true;
  # users.defaultUserShell = pkgs.fish;
}
