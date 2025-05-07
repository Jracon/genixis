{
  ...
}:

{
  system.activationScripts.create_recyclarr_directories.text = ''
    mkdir -p /mnt/media/data/recyclarr
  '';

  virtualisation.oci-containers.containers.recyclarr = {
    hostname = "recyclarr";
    image = "ghcr.io/recyclarr/recyclarr";

    environment = {
      TZ = "America/Phoenix";
    };
    pull = "newer";
    volumes = [
      "/mnt/media/data/recyclarr:/config"
    ];
    user = "1000:1000";
  };
}
