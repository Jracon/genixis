{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  imports = [ ./template.nix ];

  containers.media-managers = generateContainer "media-managers" { };
}
