{
  pkgs,
  ...
}:

{
  services.zfs.autoScrub.enable = true;

  boot.zfs.extraPools = [
    "media"
  ];
  environment.systemPackages = [
    pkgs.zfs
  ];
}
