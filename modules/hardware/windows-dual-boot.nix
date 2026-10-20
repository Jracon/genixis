{
  lib,
  local,
  pkgs,
  ...
}:

{
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

  # One-shot reboot into Windows; the next boot returns to the default entry
  environment.systemPackages = lib.mkIf (local ? windows-efi-handle) [
    (pkgs.writeShellScriptBin "reboot-windows" ''
      exec systemctl reboot --boot-loader-entry=windows_11.conf
    '')
  ];

  time.hardwareClockInLocalTime = true;
}
