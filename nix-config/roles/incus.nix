{
  interfaces, 
  ...
}:

let
  primaryInterface = builtins.elemAt interfaces 0;
in
{
  virtualisation.incus = {
    enable = true;
    preseed = {
      networks = [
        {
          name = "imv0";
          type = "macvlan";
          config = {
            parent = primaryInterface;
          };
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
    
    ui.enable = true;
  };

  networking.nftables.enable = true;
}