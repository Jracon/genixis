{
  pkgs,
  ...
}:

{
  services.zfs.autoScrub.enable = true;

  boot.zfs = {
    enable = true;

    extraPools = [
      "media"
    ];
  };
  environment.systemPackages = [
    pkgs.zfs
  ];
}
