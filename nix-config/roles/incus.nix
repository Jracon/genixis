{
  devices, 
  ...
}:

let
  primaryInterface = builtins.elemAt devices.interfaces 0;
in
  {
    networking = {
      bridges.ib0.interfaces = [ 
        primaryInterface 
      ];

      firewall.allowedTCPPorts = [ 
        8443 
      ];

      interfaces.ib0.useDHCP = true;
      interfaces.${primaryInterface}.useDHCP = false;

      nftables.enable = true;
    };

    # enable Incus (and the UI) and set preseed values
    virtualisation.incus = {
      enable = true;
      preseed = {
        config = {
          "core.https_address" = ":8443";
        };

        networks = [
          {
            name = "ib0";
            type = "bridge";

            config = {
              # "ipv4.address" = "none"; 
              "ipv6.address" = "none"; 
            };
          }
        ];

        profiles = [
          {
            name = "default";

            config = {
              "security.nesting" = "true";
            };

            devices = (
              if 
                builtins.pathExists "/dev/dri" 
              then 
                {
                  dri = {
                    type = "disk";
                    source = "/dev/dri";
                    path = "/dev/dri";
                  };
                }
              else
                { }
              ) 
              // 
              {
              eth0 = {
                name = "eth0";
                type = "nic";
                network = "ib0";
              };

              root = {
                type = "disk";
                path = "/";
                pool = "default";
              };
            };
          }
        ];

        storage_pools = [
          {
            name = "default";
            driver = "btrfs";
          }
        ];
      };
    
      ui.enable = true;
    };
  }
