{
  ...
}:
{
  boot.loader.systemd-boot.enable = true;

  fileSystems."/" = {
    device = "/dev/disk/dummy";
    fsType = "ext4";
  };

  networking.hostId = "12345678";
}
