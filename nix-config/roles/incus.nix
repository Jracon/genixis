{
  interfaces, 
  ...
}:

let
  primaryInterface = builtins.elemAt interfaces 0;
in
{
  networking.firewall.allowedTCPPorts = [ 8443 ];

  virtualisation.incus = {
    enable = true;
    preseed = {
      config = {
        "core.https_address" = ":8443";
      };

      storage_pools = [
        {
          driver = "btrfs";
          name = "default";
        }
      ];

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
            dri = {
              type = "disk";
              source = "/dev/dri";
              path = "/dev/dri";
            };

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
    };
  
    ui.enable = true;
  };

  networking.nftables.enable = true;
}