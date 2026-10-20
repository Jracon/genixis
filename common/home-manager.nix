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
      imports = lib.optional (builtins.pathExists ../users/${name}.nix) ../users/${name}.nix;
    });
  };
}
