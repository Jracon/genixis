{
  containerNames,
  lib,
  local,
  pkgs,
  ...
}:

let
  primaryInterface = builtins.elemAt local.interfaces 0;

  generateContainerModules =
    container:
    let
      containerDirectory = ../containers/${container};
    in
    if builtins.pathExists containerDirectory && builtins.isPath containerDirectory then
      let
        entries = builtins.readDir containerDirectory;
        nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
          builtins.attrNames entries
        );
      in
      builtins.map (name: containerDirectory + "/${name}") nixFiles
    else
      [ ];

  generateContainer = container: {
    autoStart = true;
    hostBridge = "br0";
    privateNetwork = true;

    extraFlags = [
      "--system-call-filter=keyctl"
      "--system-call-filter=bpf"
    ];

    config =
      {
        config,
        lib,
        pkgs,
        ...
      }:

      {
        imports = [
          ../modules/podman.nix
        ] ++ generateContainerModules container;

        networking = {
          useDHCP = lib.mkForce true;
          firewall.enable = true;
          firewall.allowedTCPPorts = [
            8989
            8990
          ];
        };
      };
  };
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

  containers = builtins.listToAttrs (
    map (container: {
      name = container;
      value = generateContainer container;
    }) containerNames
  );

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
