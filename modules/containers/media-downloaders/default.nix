{
  lib,
  local,
  ...
}:

let
  primaryInterface = builtins.elemAt local.interfaces 0;
in
{
  networking = {
    bridges.br0.interfaces = [ primaryInterface ];
    interfaces.bro.useDHCP = true;
  };

  containers.caddy = {
    autoStart = true;
    hostBridge = "br0";

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
}
