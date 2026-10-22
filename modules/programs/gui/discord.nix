{
  lib,
  pkgs,
  ...
}:

{
  # macOS installs Discord via the Homebrew cask
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.discord
  ];
}
