{
  config,
  ...
}:

let
  generateContainer = config._module.args.containerTemplate.generateContainer;
in
{
  imports = [ ./template.nix ];

  age.secrets.mealie_environment = {
    file = ../oci-containers/mealie/environment.age;
    # mode = "600";
  };

  containers.mealie = generateContainer "mealie" {
    extraBindMounts = {
      mealie_environment = {
        hostPath = "/run/agenix/mealie_environment";
        mountPoint = "/run/agenix/mealie_environment";
      };
    };
  };
}
