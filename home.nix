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
