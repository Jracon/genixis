{
  agenix,
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
      containerDirectory = ../modules/virtualisation/oci-containers/${container};
    in
    if builtins.pathExists containerDirectory && builtins.isPath containerDirectory then
      let
        entries = builtins.readDir containerDirectory;
        nixFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
          builtins.attrNames entries
        );
        modulePaths = builtins.map (name: containerDirectory + "/${name}") nixFiles;
      in
      # builtins.trace "Including modules for container ${container}: ${builtins.toString modulePaths}"
      (modulePaths)
    else
      # builtins.trace "Container directory not found: ${containerDirectory}"
      [ ];

  generateContainer =
    containerName:
    {
      extraBindMounts ? { },
      extraAllowedDevices ? [ ],
    }:
    let
      defaultBindMounts = {
        "/root/.ssh/genixis_secrets".isReadOnly = true;

        fuse = {
          hostPath = "/dev/fuse";
          mountPoint = "/dev/fuse";
          isReadOnly = false;
        };
        sys = {
          hostPath = "/sys";
          mountPoint = "/run/sys";
          isReadOnly = false;
        };
      };

      defaultAllowedDevices = [
        {
          node = "/dev/fuse";
          modifier = "rwm";
        }
        {
          node = "/sys";
          modifier = "rwm";
        }
      ];

    in
    {
      autoStart = true;
      hostBridge = "br0";
      privateNetwork = true;
      privateUsers = "pick";

      additionalCapabilities = [
        "all"
      ];
      allowedDevices = defaultAllowedDevices // extraAllowedDevices;
      bindMounts = defaultBindMounts // extraBindMounts;
      extraFlags = [
        "--system-call-filter=add_key"
        "--system-call-filter=bpf"
        "--system-call-filter=keyctl"
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
            agenix.nixosModules.default
            ../common/agenix.nix
            ../common/ssh.nix

            ../modules/virtualisation/docker.nix
          ]
          ++ generateContainerModules containerName;

          environment.systemPackages = [
            pkgs.fuse-overlayfs
          ];

          networking = {
            firewall.enable = true;
            useDHCP = lib.mkForce true;
            useHostResolvConf = lib.mkForce false;
          };
        };
    };
in
{
  config = {
    networking = {
      bridges.br0.interfaces = [ primaryInterface ];
      useNetworkd = true;

      interfaces = {
        "${primaryInterface}".useDHCP = false;
        br0.useDHCP = true;
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
  };

  config._module.args = {
    containerTemplate = {
      inherit generateContainer;
    };
  };
}
