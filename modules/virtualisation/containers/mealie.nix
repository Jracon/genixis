{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  age.secrets.mealie_environment = {
    file = ./environment.age;
    # mode = "600";
  };

  imports = [ ./template.nix ];

  containers.mealie = generateContainer "mealie" {
    extraExtraFlags = [
      "--set-credential=mealie_environment:${config.age.secrets.mealie_environment.path}"
    ];
  };
}
