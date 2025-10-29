{
  ...
}:

{
  boot.zfs.extraPools = [ "media" ];

  services.zfs.autoScrub.enable = true;
}
