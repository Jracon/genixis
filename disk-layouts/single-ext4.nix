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

    content = {
      type = "gpt";

      partitions = {
        boot = {
          type = "EF02";

          size = "1M";
        };
        ESP = {
          type = "EF00";

          content = {
            type = "filesystem";

            format = "vfat";
            mountOptions = [
              "umask=0077"
            ];
            mountpoint = "/boot";
          };
          size = "1G";
        };
        root = {
          content = {
            type = "filesystem";

            format = "ext4";
            mountpoint = "/";
          };
          size = "100%";
        };
      };
    };
    device = primaryDisk;
  };
}
