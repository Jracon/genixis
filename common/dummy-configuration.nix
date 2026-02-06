{
  ...
}:

{
  boot.loader.systemd-boot.enable = true;

  networking.hostId = "12345678";

  system.stateVersion = "26.05";

  fileSystems."/" = {
    device = "/dev/disk/dummy";
    fsType = "ext4";
  };
}
