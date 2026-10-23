{
  lib,
  pkgs,
  ...
}:

{
  # macOS installs Spotify via the Homebrew cask
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.spotify
  ];
}
