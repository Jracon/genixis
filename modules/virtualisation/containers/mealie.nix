{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  age.secrets.mealie_environment = {
    file = ../oci-containers/mealie/environment.age;
    # mode = "600";
  };

  imports = [ ./template.nix ];

  containers.mealie = generateContainer "mealie" {
    extraBindMounts = {
      "${config.age.secrets.mealie_environment.path}".isReadOnly = true;
    };
  };
}
