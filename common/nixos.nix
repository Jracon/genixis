{
  homeUsers,
  lib,
  pkgs,
  ...
}:

{
  boot.loader = {
    generic-extlinux-compatible.configurationLimit = 5;
    grub.configurationLimit = 5;
    systemd-boot.configurationLimit = 5;
  };

  environment.systemPackages = [
    pkgs.isd
  ];

  programs = {
    fish.enable = true;
    nix-ld.enable = true;
  };

  users = {
    defaultUserShell = pkgs.fish;
    # merges with any definition in /etc/nixos/configuration.nix
    users = lib.genAttrs (lib.remove "root" homeUsers) (_: {
      isNormalUser = true;
    });
  };
}
