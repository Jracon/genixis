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
      containerDirectory = ./modules/containers/${container};
      files =
        if builtins.pathExists containerDirectory then
          lib.filterSource (
            path: type: type == "file" && builtins.match ".+\\.nix$" path != null
          ) containerDirectory
        else
          { };
    in
    builtins.attrValues files;

  generateContainer = container: {
    autoStart = true;
    hostBridge = "br0";
    privateNetwork = true;

    additionalCapabilities = [
      "CAP_SETUID"
      "CAP_SETGID"
    ];

    config =
      {
        ...
      }:

      {
        imports = [
          ../modules/podman.nix
        ];

        networking = {
          useDHCP = lib.mkForce true;
          firewall.enable = true;
          firewall.allowedTCPPorts = [
            8989
            8990
          ];

          useHostResolvConf = lib.mkForce false;
        };

        system.activationScripts.create_sonarr_directories.text = ''
          mkdir -p /mnt/sonarr /mnt/media /mnt/sonarr-anime
        '';

        users.users.root = {
          subUidRanges = [
            {
              startUid = 1000;
              count = 1;
            }
          ];
          subGidRanges = [
            {
              startGid = 1000;
              count = 1;
            }
          ];
        };

        virtualisation.oci-containers.containers = {
          sonarr = {
            image = "lscr.io/linuxserver/sonarr:latest";
            pull = "newer";
            hostname = "sonarr";

            environment = {
              PUID = "1000";
              PGID = "1000";
              TZ = "America/Phoenix";
            };

            volumes = [
              "/mnt/sonarr:/config"
              "/mnt/media:/mnt/media"
            ];

            ports = [
              "8989:8989"
            ];
          };

          sonarr-anime = {
            image = "lscr.io/linuxserver/sonarr:latest";
            pull = "newer";
            hostname = "sonarr-anime";

            environment = {
              PUID = "1000";
              PGID = "1000";
              TZ = "America/Phoenix";
            };

            volumes = [
              "/mnt/sonarr-anime:/config"
              "/mnt/media:/mnt/media"
            ];

            ports = [
              "8990:8989"
            ];
          };
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
