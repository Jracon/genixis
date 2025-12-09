{
  config,
  ...
}:

{
  age.secrets.recyclarr_config = {
    file = ./recyclarr/config.age;
    group = "1000";
    mode = "400";
    owner = "1000";
  };

  system.activationScripts.create_recyclarr_directory.text = ''
    mkdir -p /mnt/recyclarr/configs && chown 1000:1000 -R /mnt/recyclarr
  '';

  virtualisation.oci-containers.containers.recyclarr = {
    image = "ghcr.io/recyclarr/recyclarr";

    hostname = "recyclarr";
    pull = "newer";
    user = "1000:1000";

    environment = {
      TZ = "America/Phoenix";
    };
    volumes = [
      "/mnt/recyclarr:/config"
      "${config.age.secrets.recyclarr_config.path}:/config/configs/recyclarr.yml"
    ];
  };
}
