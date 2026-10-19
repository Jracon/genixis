{
  lib,
  ...
}:

{
  # wsl.defaultUser is left to /etc/nixos/configuration.nix, since renaming
  # the default user on an existing install needs extra manual steps
  wsl.enable = true;

  # WSL has no bootloader; overrides dummy-configuration.nix during CI checks
  boot.loader.systemd-boot.enable = lib.mkForce false;
}
