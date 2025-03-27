{
  devices,
  ...
}:

let
  primaryInterface = builtins.readFile (pkgs.runCommand "primaryInterface" {} ''
      mkdir -p $out
      ip route | grep default | awk "{print \$5}" > $out/interface
    '' + "/interface"); # builtins.elemAt devices.interfaces 0;
in
{
  networking = {
    bridges.eb0.interfaces = [
      primaryInterface
    ];

    firewall.allowedTCPPorts = [
      8443
    ];

    interfaces.eb0 = {
      useDHCP = true;
    };

    nftables.enable = true;

    useDHCP = false;
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
            "ipv4.address" = "auto";
            "ipv4.nat" = "true";
            "ipv6.address" = "auto";
            "ipv6.nat" = "true";
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

          devices =
            (
              if builtins.pathExists "/dev/dri" then
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
            // {
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
