{
  config, 
  ...
}:

{
  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = [
        {
          name = "imv0";
          type = "macvlan";
          parent = config.networking.defaultInterface;
        }
      ];

      profiles = [
        {
          name = "default";

          devices = {
            eth0 = {
              name = "eth0";
              network = "imv0";
              type = "nic";
            };

            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          };
        }
      ];

      storage_pools = [
        {
          driver = "btrfs";
          name = "default";
        }
      ];
    };
  };

  networking.nftables.enable = true;
}