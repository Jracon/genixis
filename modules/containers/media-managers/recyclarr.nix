{
  ...
}:

{
  age.secrets.recyclarr_config.file = ./recyclarr/config.age;

  system.activationScripts.create_recyclarr_directory.text = ''
    mkdir -p /mnt/recyclarr
  '';

  virtualisation.oci-containers.containers.recyclarr = {
    image = "ghcr.io/recyclarr/recyclarr";
    pull = "newer";
    hostname = "recyclarr";
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
