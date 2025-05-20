{
  local, 
  ...
}:

let
  primaryInterface = builtins.elemAt local.interfaces 0;
in
  {
    systemd.network.enable = true;

    networking = {
      nftables.enable = true;
      useNetworkd = true;

      bridges.eb0.interfaces = [
        primaryInterface
      ];

      firewall = {
        allowedTCPPorts = [
          8443
        ];

        interfaces.eb0 = {
          allowedTCPPorts = [
            53
            67
          ];

          allowedUDPPorts = [
            53
            67
          ];
        };
      };

      interfaces = {
        "${primaryInterface}".useDHCP = false;
        eb0.useDHCP = true;
      };
    };

    # enable Incus (and the UI) and set preseed values
    virtualisation.incus = {
      enable = true;
      ui.enable = true;

      preseed = {
        config = {
          "core.https_address" = ":8443";
        };

        networks = [
          {
            name = "ib0";
            type = "bridge";

            config = {
              "ipv4.address" = "none";
              "ipv4.dhcp" = "false";
              "ipv4.nat" = "false";
              "ipv6.address" = "none";
              "ipv6.nat" = "false";
            };
          }
        ];

        profiles = [
          {
            name = "default";

            config = {
              "security.nesting" = "true";
              "security.syscalls.intercept.mknod" = "true";
              "security.syscalls.intercept.setxattr" = "true";
            };

            devices = {
              eth0 = {
                name = "eth0";
                nictype = "bridged";
                type = "nic";
                parent = "eb0";
              };

              root = {
                type = "disk";
                path = "/";
                pool = "default";
              };
            };
          }
        ] 
        ++ 
        (
          if builtins.pathExists "/dev/dri" then 
            [
              {
                name = "gpu-enabled";

                devices = {
                  dri = {
                    type = "disk";
                    source = "/dev/dri";
                    path = "/dev/dri";
                  };
                };
              }
            ] 
          else 
            [ ]
        )
        ++ 
        (
          if builtins.pathExists "/dev/net/tun" then 
            [
              {
                name = "vpn-capable";

                config = {
                  "raw.lxc" = "lxc.cgroup.devices.allow = c 10:200 rwm";
                };

                devices = {
                  tun = {
                    type = "unix-char";
                    path = "/dev/net/tun";
                    major = 10;
                    minor = 200;
                  };
                };
              }
            ] 
          else 
            []
        );

        storage_pools = [
          {
            name = "default";
            driver = "btrfs";
          }
        ];
      };
    };
  }
