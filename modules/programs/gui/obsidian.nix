{
  lib,
  pkgs,
  ...
}:

{
  # macOS installs Obsidian via the Homebrew cask
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    pkgs.obsidian
  ];
}
