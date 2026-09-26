{
  lib,
  local,
  ...
}:

{
  time.hardwareClockInLocalTime = true;

  boot = {
    loader.systemd-boot = {
      edk2-uefi-shell.enable = true;

      windows = lib.mkIf (local ? windows-efi-handle) {
        "11" = {
          efiDeviceHandle = local.windows-efi-handle;
          title = "Windows 11";
        };
      };
    };
    supportedFilesystems = [
      "ntfs"
    ];
  };
}
