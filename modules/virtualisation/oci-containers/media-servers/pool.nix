{
  services.zfs.autoScrub.enable = true;

  boot.zfs.extraPools = [
    "media"
  ];
}
