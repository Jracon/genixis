{
  config,
  ...
}:

let
  # the shared shapes of the container modules (lib/oci-containers.nix)
  oci = import ../../../../lib/oci-containers.nix;
in
{
  age.secrets.recyclarr_config = {
    file = ./recyclarr/config.age;
    group = toString oci.mediaId;
    mode = "400";
    owner = toString oci.mediaId;
  };

  system.activationScripts.create_recyclarr_directory.text = ''
    mkdir -p /mnt/recyclarr/configs && chown ${oci.mediaUser} -R /mnt/recyclarr
  '';

  virtualisation.oci-containers.containers.recyclarr = {
    image = "ghcr.io/recyclarr/recyclarr";

    hostname = "recyclarr";
    pull = "newer";
    user = oci.mediaUser;

    environment = {
      TZ = config.time.timeZone;
    };
    volumes = [
      "/mnt/recyclarr:/config"
      "${config.age.secrets.recyclarr_config.path}:/config/configs/recyclarr.yml"
    ];
  };
}
