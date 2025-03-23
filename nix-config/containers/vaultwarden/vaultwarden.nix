{
  config, 
  ...
}:

{
  age.secrets.vaultwarden_environment = {
    file = ./environment.age;
    mode = "600";
  };

  virtualisation.oci-containers.containers = {
    vaultwarden = {
      hostname = "vaultwarden";
      image = "vaultwarden/server:latest";

      environmentFiles = [
        config.age.secrets.vaultwarden_environment.path
      ];
      pull = "always";
      volumes = [
        "/mnt/vaultwarden:/data"
      ];
    };
  };
}
