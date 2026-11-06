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

  # the LAN address of services; the LAN is the primary transport of the forge, and the
  # Tailscale subnet route carries the address off the LAN (issue #166, reversal of 2026-11-06)
  networking.hosts."10.0.0.208" = [
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
