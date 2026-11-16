{
  config,
  lib,
  pkgs,
  ...
}:

let
  username = config.home.username;
in
{
  home = {
    # the extension of the collision backups of every home. One option
    # decides it for a home of a system build and for the standalone rehome
    # of fish.nix, which passes no extension flag
    backupFileExtension = "backup";

    # set by the NixOS/nix-darwin Home Manager module; only needed for standalone homeConfigurations
    homeDirectory = lib.mkDefault (
      if pkgs.stdenv.hostPlatform.isDarwin then
        "/Users/${username}"
      else if username == "root" then
        "/root"
      else
        "/home/${username}"
    );
    stateVersion = "25.05";
  };
}
