{
  homeModules,
  homeUsers,
  lib,
  ...
}:

{
  home-manager = {
    backupFileExtension = "backup";
    sharedModules = homeModules;
    useGlobalPkgs = true;
    useUserPackages = true;
    users = lib.genAttrs homeUsers (name: {
      imports = import ../lib/user-module.nix name;
    });
  };
}
