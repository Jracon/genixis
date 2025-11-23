{
  pkgs,
  ...
}:

{
  services.zfs.autoScrub.enable = true;

  boot = {
    supportedFilesystems = [
      "zfs"
    ];
    zfs.extraPools = [
      "media"
    ];
  };
  environment.systemPackages = [
    pkgs.zfs
  ];
}
