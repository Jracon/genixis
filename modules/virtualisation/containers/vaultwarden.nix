{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  imports = [
    ./template.nix
  ];

  containers.vaultwarden = generateContainer "vaultwarden" { };
}
