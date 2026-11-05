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

  # the tailnet address of services; the tailnet is the primary transport of the forge (issue #166)
  networking.hosts."100.105.66.33" = [
    "forgejo.local.jracon.xyz"
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
