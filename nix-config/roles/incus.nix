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
          parent = builtins.readFile "/proc/net/route" |> builtins.split "\n" |> builtins.head |> builtins.split "\t" |> builtins.elemAt 0;
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