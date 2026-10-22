{
  config,
  lib,
  ...
}:

let
  syncthing = import ../../syncthing.nix { inherit lib; };
in
{
  services.syncthing = {
    enable = true;

    dataDir = "/mnt/syncthing";
    openDefaultPorts = true;
    settings = syncthing.settingsFor {
      hostName = config.networking.hostName;
      root = config.services.syncthing.dataDir;
    };
  };
}
