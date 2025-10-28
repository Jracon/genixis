{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  imports = [ ./template.nix ];

  containers.mealie = generateContainer "mealie" { };
}
