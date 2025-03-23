{
  config, 
  ...
}:

{
  age.secrets = {
    vaultwarden_domain.file = ./domain.age;
  };

  virtualisation.oci-containers.containers = {
    vaultwarden = {
      hostname = "vaultwarden";
      image = "vaultwarden/server:latest";

      environment = {
        DOMAIN = lib.mkForce ''$(cat ${config.age.secrets.vaultwarden_domain.path})'';
        SIGNUPS_ALLOWED = "true";
      };
      pull = "always";
      volumes = [
        "/mnt/vaultwarden:/data"
      ];
    };
  };
}
