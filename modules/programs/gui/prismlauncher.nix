{
  lib,
  pkgs,
  ...
}:

{
  programs.prismlauncher = {
    enable = true;

    # macOS installs Prism Launcher via the Homebrew cask
    package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin null;
  };
}
