{
  lib,
}:

# The Syncthing topology, shared by the NixOS service (modules/services/syncthing.nix) and the
# Home Manager module (modules/programs/cli/syncthing.nix). The structure is committed; the device
# IDs are not. Edit `devices` and `folders` below.
#
# Device names are hostnames (`networking.hostName`): a host only syncs the folders that list it,
# and a host that isn't a declared device syncs nothing.
#
# Device IDs live in each machine's uncommitted local.nix (/etc/nixos/local.nix or
# /etc/nix-darwin/local.nix) as `syncthing-device-ids = { <hostname> = "<id>"; ... };`, listing every
# other device it should talk to. A peer without an ID there is skipped, so builds without a
# local.nix (CI) still evaluate. Get a device's ID from `syncthing device-id` once it has run.
#
# Each folder lists the devices that share it. A device's `type` is its own permission for the
# folder: "sendreceive" (default), "sendonly" (its changes go out, remote changes are ignored) or
# "receiveonly" (remote changes come in, its own changes stay local). `versioning` is optional and
# applies on every device, e.g. { type = "trashcan"; params.cleanoutDays = "30"; }.
#
#   devices = [
#     "desktop"
#     "media"
#   ];
#   folders = {
#     documents = {
#       devices = {
#         desktop = { };
#         media.type = "receiveonly";
#       };
#       versioning.type = "simple";
#     };
#   };
let
  topology = {
    devices = [ ];
    folders = { };
  };

  localPath = lib.findFirst builtins.pathExists null [
    /etc/nixos/local.nix
    /etc/nix-darwin/local.nix
  ];
  deviceIds = if localPath == null then { } else (import localPath).syncthing-device-ids or { };

  unknown = lib.concatMap (
    folder: lib.filter (name: !(lib.elem name topology.devices)) (lib.attrNames folder.devices)
  ) (lib.attrValues topology.folders);
in
assert lib.assertMsg (
  unknown == [ ]
) "lib/syncthing.nix: folders share with undeclared devices: ${toString unknown}";
{
  # services.syncthing.settings for `hostName`, with folders at <root>/<folder name>
  settingsFor =
    {
      hostName,
      root,
    }:
    let
      peers = lib.filter (name: name != hostName && deviceIds ? ${name}) topology.devices;
    in
    lib.optionalAttrs (lib.elem hostName topology.devices) {
      devices = lib.genAttrs peers (name: {
        id = deviceIds.${name};
      });
      folders = lib.mapAttrs (name: folder: {
        devices = lib.filter (peer: folder.devices ? ${peer}) peers;
        path = "${root}/${name}";
        type = folder.devices.${hostName}.type or "sendreceive";
        versioning = folder.versioning or null;
      }) (lib.filterAttrs (_: folder: folder.devices ? ${hostName}) topology.folders);
      options.urAccepted = -1; # no usage reporting, and no first-run prompt about it
    };
}
