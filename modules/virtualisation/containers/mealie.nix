{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{

  imports = [ ./template.nix ];

  containers.mealie = generateContainer "mealie" {
    extraExtraFlags = [
      "--bind-ro=${config.age.secrets.mealie_environment.path}:/mnt/mealie_environment:idmap"
    ];
  };
}
