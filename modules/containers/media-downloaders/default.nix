{
  lib,
  local,
  pkgs,
  ...
}:

let
  primaryInterface = builtins.elemAt local.interfaces 0;
in
{
  networking = {
    bridges.br0.interfaces = [ primaryInterface ];
    useNetworkd = true;

    interfaces = {
      "${primaryInterface}".useDHCP = false;
      br0.useDHCP = true;
    };
  };

  containers.caddy = {
    autoStart = true;
    # hostBridge = "br0";
    privateNetwork = true;

    config =
      {
        config,
        pkgs,
        lib,
        ...
      }:
      {
        networking = {
          useDHCP = lib.mkForce true;
          firewall.enable = true;
        };
      };
  };

  systemd.services.set-br0-mac = {
    after = [
      "systemd-networkd.service"
      "sys-subsystem-net-devices-${primaryInterface}.device"
      "network-online.target"
    ];

    path = [
      "/run/current-system/sw"
    ];

    requires = [
      "systemd-networkd.service"
    ];

    serviceConfig = {
      Type = "oneshot";

      ExecStart = pkgs.writeShellScript "set-br0-mac" ''
        mac=$(cat /sys/class/net/${primaryInterface}/address)
        ip link set dev br0 down
        ip link set dev br0 address "$mac"
        ip link set dev br0 up
      '';
    };

    wantedBy = [
      "multi-user.target"
    ];

    wants = [
      "network-online.target"
    ];
  };
}
