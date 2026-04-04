{
  config,
  lib,
  pkgs,
  ...
}:

{
  system-manager.allowAnyDistro = true;

  environment.etc = {
    "nix/nix.conf".replaceExisting = true;
  };
}
