{
  config,
  ...
}:

{
  age.secrets.mealie_environment = {
    file = ./environment.age;
    # mode = "600";
  };

  networking.firewall.allowedTCPPorts = [
    9925
  ];

  system.activationScripts.create_mealie_directory.text = ''
    mkdir -p /mnt/mealie
  '';

  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:v2.8.0";

    hostname = "mealie";
    pull = "newer";

    environmentFiles = [
      config.age.secrets.mealie_environment.path
    ];
    ports = [
      "9925:9000"
    ];
    volumes = [
      "/mnt/mealie:/app/data"
    ];
  };
}
