{
  local,
  ...
}:

let
  primaryDisk = builtins.elemAt local.disks 0;
in
{
  disko.devices.disk.main = {
    type = "disk";
    device = primaryDisk;

    content = {
      type = "gpt";

      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "1G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";

          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
