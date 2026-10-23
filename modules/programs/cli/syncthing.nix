{
  config,
  lib,
  osConfig ? null, # the NixOS/nix-darwin config; absent in standalone homeConfigurations
  ...
}:

let
  syncthing = import ../../../lib/syncthing.nix { inherit lib; };

  hostName = if osConfig == null then null else osConfig.networking.hostName;
  settings = lib.optionalAttrs (hostName != null) (
    syncthing.settingsFor {
      inherit hostName;

      root = "${config.home.homeDirectory}/Sync";
    }
  );
in
{
  # root only exists on hosts for system administration, never as a sync endpoint
  services.syncthing = lib.mkIf (config.home.username != "root" && settings != { }) {
    inherit settings;

    enable = true;
  };
}
