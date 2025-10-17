{
  local,
  ...
}:

let
  primaryInterface = builtins.elemAt local.interfaces 0;
in
{
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = primaryInterface;
  };

  containers.caddy = {
    autoStart = true;
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
          firewall = {
            enable = true;
          };
        };
      };
  };
}
